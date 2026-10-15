namespace Soopi.Backend.Services
{
    public interface IOtpService
    {
        Task<(bool Success, string Message, int? CooldownSeconds, int? ExpiresInMinutes, string? DevOtp)> SendRegistrationOtpAsync(string email, string? clientIp = null);
        Task<(bool Success, string Message, string? VerificationToken, int? RemainingAttempts)> VerifyRegistrationOtpAsync(string email, string otp);
        bool IsVerificationTokenValid(string email, string token);
    }
}
