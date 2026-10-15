using System.Net;
using System.Net.Mail;

namespace Soopi.Backend.Services
{
    public class EmailService : IEmailService
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<EmailService> _logger;

        public EmailService(IConfiguration configuration, ILogger<EmailService> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public async Task SendOtpEmailAsync(string toEmail, string otpCode, int expiryMinutes)
        {
            var host = _configuration["EmailSettings:SmtpHost"] ?? "smtp.gmail.com";
            var port = int.TryParse(_configuration["EmailSettings:SmtpPort"], out var p) ? p : 587;
            var senderEmail = _configuration["EmailSettings:SenderEmail"];
            var senderPassword = _configuration["EmailSettings:SenderPassword"];
            var senderName = _configuration["EmailSettings:SenderName"] ?? "SOOPI FOOD";
            var enableSsl = bool.TryParse(_configuration["EmailSettings:EnableSsl"], out var ssl) ? ssl : true;

            // Nếu chưa cấu hình email hoặc mật khẩu, chỉ ghi log để phục vụ dev/test
            if (string.IsNullOrWhiteSpace(senderEmail) || string.IsNullOrWhiteSpace(senderPassword))
            {
                _logger.LogWarning("[DEV MODE - EMAIL CHƯA CẤU HÌNH] Mã OTP gửi tới {Email} là: {Otp} (Hết hạn sau {Expiry} phút)", toEmail, otpCode, expiryMinutes);
                return;
            }

            try
            {
                using var client = new SmtpClient(host, port)
                {
                    Credentials = new NetworkCredential(senderEmail, senderPassword),
                    EnableSsl = enableSsl
                };

                var mailMessage = new MailMessage
                {
                    From = new MailAddress(senderEmail, senderName),
                    Subject = $"[{senderName}] Mã xác thực OTP đăng ký: {otpCode}",
                    Body = GenerateOtpEmailTemplate(otpCode, expiryMinutes, senderName),
                    IsBodyHtml = true
                };

                mailMessage.To.Add(toEmail);

                await client.SendMailAsync(mailMessage);
                _logger.LogInformation("Đã gửi email OTP thành công tới: {Email}", toEmail);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi khi gửi email OTP tới {Email}. Mã OTP dự phòng: {Otp}", toEmail, otpCode);
                // Không throw exception để không làm ngắt quãng flow nếu SMTP gặp trục trặc mạng
            }
        }

        private static string GenerateOtpEmailTemplate(string otpCode, int expiryMinutes, string senderName)
        {
            return $@"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>Mã xác thực OTP</title>
</head>
<body style='font-family: Arial, sans-serif; background-color: #f7f7f7; margin: 0; padding: 20px;'>
    <div style='max-width: 540px; margin: 0 auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.06);'>
        <!-- Header -->
        <div style='background: linear-gradient(135deg, #FF9800, #F57C00); padding: 32px 24px; text-align: center; color: white;'>
            <h1 style='margin: 0; font-size: 28px; font-weight: 800; letter-spacing: 1px;'>{senderName}</h1>
            <p style='margin: 8px 0 0; font-size: 14px; opacity: 0.9;'>Xác thực đăng ký tài khoản</p>
        </div>

        <!-- Content -->
        <div style='padding: 32px 24px; text-align: center; color: #333333;'>
            <p style='font-size: 16px; line-height: 1.5; margin: 0 0 20px;'>
                Xin chào quý khách,<br/>
                Bạn vừa yêu cầu tạo tài khoản mới tại <b>{senderName}</b>. Vui lòng nhập mã xác thực OTP bên dưới để hoàn tất đăng ký:
            </p>

            <!-- OTP Box -->
            <div style='margin: 28px 0; display: inline-block;'>
                <div style='font-size: 36px; font-weight: 900; letter-spacing: 10px; color: #E65100; background: #FFF3E0; padding: 16px 32px; border-radius: 12px; border: 2px dashed #FF9800;'>
                    {otpCode}
                </div>
            </div>

            <p style='font-size: 14px; color: #666666; margin: 16px 0 24px;'>
                ⏱️ Mã này có hiệu lực trong vòng <b>{expiryMinutes} phút</b>.<br/>
                🛡️ Vì lý do an toàn bảo mật, vui lòng <b>không chia sẻ mã này</b> cho bất kỳ ai.
            </p>

            <div style='height: 1px; background: #EEEEEE; margin: 24px 0;'></div>

            <p style='font-size: 12px; color: #999999; margin: 0;'>
                Nếu bạn không thực hiện yêu cầu đăng ký này, vui lòng bỏ qua email.<br/>
                © {DateTime.UtcNow.Year} {senderName}. Tất cả các quyền được bảo lưu.
            </p>
        </div>
    </div>
</body>
</html>";
        }
    }
}
