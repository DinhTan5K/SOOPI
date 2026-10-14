using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Soopi.Backend.DataAccess.Repositories;

namespace Soopi.Backend.Services
{
    public class OtpService : IOtpService
    {
        private readonly IMemoryCache _cache;
        private readonly IUserRepository _userRepository;
        private readonly IEmailService _emailService;
        private readonly IWebHostEnvironment _env;
        private readonly IConfiguration _configuration;
        private readonly ILogger<OtpService> _logger;

        private const int OtpExpiryMinutes = 5;
        private const int ResendCooldownSeconds = 60;
        private const int MaxFailedAttempts = 5;
        private const int MaxSendsPerHour = 5;

        private class OtpEntry
        {
            public string Code { get; set; } = string.Empty;
            public DateTime CreatedAt { get; set; }
            public DateTime ExpiresAt { get; set; }
            public int FailedAttempts { get; set; }
        }

        private class RateLimitTracker
        {
            public DateTime FirstRequestAt { get; set; }
            public int RequestCount { get; set; }
            public DateTime LastSentAt { get; set; }
        }

        public OtpService(
            IMemoryCache cache,
            IUserRepository userRepository,
            IEmailService emailService,
            IWebHostEnvironment env,
            IConfiguration configuration,
            ILogger<OtpService> logger)
        {
            _cache = cache;
            _userRepository = userRepository;
            _emailService = emailService;
            _env = env;
            _configuration = configuration;
            _logger = logger;
        }

        public async Task<(bool Success, string Message, int? CooldownSeconds, int? ExpiresInMinutes, string? DevOtp)> SendRegistrationOtpAsync(string email, string? clientIp = null)
        {
            var normalizedEmail = email.Trim().ToLowerInvariant();

            // 1. Kiểm tra định dạng Email
            if (!Regex.IsMatch(normalizedEmail, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
            {
                return (false, "Địa chỉ email không đúng định dạng.", null, null, null);
            }

            // 2. Chống spam đăng ký đè: Kiểm tra xem email đã tồn tại trong hệ thống chưa
            try
            {
                var existingUser = await _userRepository.GetByEmailAsync(normalizedEmail);
                if (existingUser != null)
                {
                    return (false, "Email này đã được sử dụng. Vui lòng đăng nhập hoặc chọn Quên mật khẩu.", null, null, null);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning("Không thể kiểm tra trùng lặp email từ database: {Message}", ex.Message);
            }

            // 3. Chống Spam: Rate Limiting & Cooldown
            var rateKey = $"rate_limit_otp_{normalizedEmail}";
            var now = DateTime.UtcNow;

            if (_cache.TryGetValue(rateKey, out RateLimitTracker? tracker) && tracker != null)
            {
                // Kiểm tra Cooldown 60s
                var elapsedSinceLastSent = (now - tracker.LastSentAt).TotalSeconds;
                if (elapsedSinceLastSent < ResendCooldownSeconds)
                {
                    var waitSeconds = ResendCooldownSeconds - (int)elapsedSinceLastSent;
                    return (false, $"Vui lòng chờ {waitSeconds} giây trước khi yêu cầu gửi lại mã OTP.", waitSeconds, null, null);
                }

                // Kiểm tra giới hạn số lần gửi trong 1 giờ
                if ((now - tracker.FirstRequestAt).TotalHours < 1)
                {
                    if (tracker.RequestCount >= MaxSendsPerHour)
                    {
                        return (false, "Bạn đã gửi quá nhiều yêu cầu xác thực trong 1 giờ. Vui lòng thử lại sau.", null, null, null);
                    }
                    tracker.RequestCount++;
                    tracker.LastSentAt = now;
                }
                else
                {
                    // Reset khung giờ mới
                    tracker.FirstRequestAt = now;
                    tracker.RequestCount = 1;
                    tracker.LastSentAt = now;
                }
            }
            else
            {
                tracker = new RateLimitTracker
                {
                    FirstRequestAt = now,
                    LastSentAt = now,
                    RequestCount = 1
                };
                _cache.Set(rateKey, tracker, TimeSpan.FromHours(1));
            }

            // 4. Sinh mã OTP 6 chữ số an toàn
            var otpCode = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();

            // 5. Lưu vào cache với thời hạn 5 phút
            var otpKey = $"otp_reg_{normalizedEmail}";
            var otpEntry = new OtpEntry
            {
                Code = otpCode,
                CreatedAt = now,
                ExpiresAt = now.AddMinutes(OtpExpiryMinutes),
                FailedAttempts = 0
            };
            _cache.Set(otpKey, otpEntry, TimeSpan.FromMinutes(OtpExpiryMinutes));

            // 6. Gửi email xác thực OTP
            await _emailService.SendOtpEmailAsync(normalizedEmail, otpCode, OtpExpiryMinutes);

            // 7. Xác định devOtp phục vụ dev test nếu chưa có SMTP
            string? devOtp = null;
            var smtpSender = _configuration["EmailSettings:SenderEmail"];
            if (_env.IsDevelopment() || string.IsNullOrWhiteSpace(smtpSender))
            {
                devOtp = otpCode;
            }

            _logger.LogInformation("Đã cấp mã OTP đăng ký cho email: {Email}", normalizedEmail);

            return (true, "Mã xác thực OTP đã được gửi đến email của bạn.", ResendCooldownSeconds, OtpExpiryMinutes, devOtp);
        }

        public Task<(bool Success, string Message, string? VerificationToken, int? RemainingAttempts)> VerifyRegistrationOtpAsync(string email, string otp)
        {
            var normalizedEmail = email.Trim().ToLowerInvariant();
            var trimmedOtp = otp.Trim();
            var otpKey = $"otp_reg_{normalizedEmail}";

            if (!_cache.TryGetValue(otpKey, out OtpEntry? entry) || entry == null)
            {
                return Task.FromResult((false, "Mã OTP đã hết hạn hoặc chưa được tạo. Vui lòng nhấn gửi lại mã.", (string?)null, (int?)0));
            }

            if (DateTime.UtcNow > entry.ExpiresAt)
            {
                _cache.Remove(otpKey);
                return Task.FromResult((false, "Mã OTP đã hết hạn. Vui lòng yêu cầu mã mới.", (string?)null, (int?)0));
            }

            // Kiểm tra số lần nhập sai
            if (entry.FailedAttempts >= MaxFailedAttempts)
            {
                _cache.Remove(otpKey);
                return Task.FromResult((false, "Bạn đã nhập sai mã OTP quá 5 lần. Mã đã bị hủy vì lý do bảo mật.", (string?)null, (int?)0));
            }

            if (!string.Equals(entry.Code, trimmedOtp, StringComparison.Ordinal))
            {
                entry.FailedAttempts++;
                var remaining = MaxFailedAttempts - entry.FailedAttempts;
                if (remaining <= 0)
                {
                    _cache.Remove(otpKey);
                    return Task.FromResult((false, "Mã OTP không chính xác. Bạn đã hết số lần thử.", (string?)null, (int?)0));
                }

                return Task.FromResult((false, $"Mã OTP không chính xác. Bạn còn {remaining} lần thử.", (string?)null, (int?)remaining));
            }

            // Xác thực thành công -> Hủy mã OTP để không thể tái sử dụng
            _cache.Remove(otpKey);

            // Sinh Verification Token hợp lệ trong 10 phút để xác thực khi hoàn tất đăng ký
            var token = Guid.NewGuid().ToString("N");
            var verifiedKey = $"verified_reg_{normalizedEmail}";
            _cache.Set(verifiedKey, token, TimeSpan.FromMinutes(10));

            _logger.LogInformation("Xác thực OTP thành công cho email: {Email}", normalizedEmail);

            return Task.FromResult((true, "Xác thực OTP thành công.", (string?)token, (int?)null));
        }

        public bool IsVerificationTokenValid(string email, string token)
        {
            var normalizedEmail = email.Trim().ToLowerInvariant();
            var verifiedKey = $"verified_reg_{normalizedEmail}";
            if (_cache.TryGetValue(verifiedKey, out string? cachedToken) && !string.IsNullOrEmpty(cachedToken))
            {
                return string.Equals(cachedToken, token, StringComparison.Ordinal);
            }
            return false;
        }
    }
}
