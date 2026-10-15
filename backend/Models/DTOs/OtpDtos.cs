using System.ComponentModel.DataAnnotations;

namespace Soopi.Backend.Models.DTOs
{
    public class SendOtpRequestDto
    {
        [Required(ErrorMessage = "Email không được để trống")]
        [EmailAddress(ErrorMessage = "Địa chỉ email không đúng định dạng")]
        public string Email { get; set; } = string.Empty;
    }

    public class VerifyOtpRequestDto
    {
        [Required(ErrorMessage = "Email không được để trống")]
        [EmailAddress(ErrorMessage = "Địa chỉ email không đúng định dạng")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mã OTP không được để trống")]
        [StringLength(6, MinimumLength = 6, ErrorMessage = "Mã OTP phải có đúng 6 chữ số")]
        public string Otp { get; set; } = string.Empty;
    }

    public class OtpResponseDto
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public int? CooldownSeconds { get; set; }
        public int? ExpiresInMinutes { get; set; }
        public string? DevOtp { get; set; }
        public string? VerificationToken { get; set; }
        public int? RemainingAttempts { get; set; }
    }
}
