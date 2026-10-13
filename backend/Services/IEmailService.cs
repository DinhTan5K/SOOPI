namespace Soopi.Backend.Services
{
    public interface IEmailService
    {
        Task SendOtpEmailAsync(string toEmail, string otpCode, int expiryMinutes);
    }
}
