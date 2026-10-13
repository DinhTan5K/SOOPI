using Microsoft.AspNetCore.Mvc;
using Soopi.Backend.Models.DTOs;
using Soopi.Backend.Services;

namespace Soopi.Backend.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly IOtpService _otpService;
        private readonly ILogger<AuthController> _logger;

        public AuthController(IOtpService otpService, ILogger<AuthController> logger)
        {
            _otpService = otpService;
            _logger = logger;
        }

        /// <summary>
        /// Gửi mã xác thực OTP qua Email khi đăng ký tài khoản (có cơ chế chống spam)
        /// </summary>
        [HttpPost("send-registration-otp")]
        public async Task<ActionResult<OtpResponseDto>> SendRegistrationOtp([FromBody] SendOtpRequestDto dto)
        {
            if (!ModelState.IsValid)
            {
                return BadRequest(new OtpResponseDto
                {
                    Success = false,
                    Message = "Dữ liệu không hợp lệ."
                });
            }

            var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString();
            var result = await _otpService.SendRegistrationOtpAsync(dto.Email, clientIp);

            if (!result.Success)
            {
                if (result.CooldownSeconds.HasValue)
                {
                    return StatusCode(StatusCodes.Status429TooManyRequests, new OtpResponseDto
                    {
                        Success = false,
                        Message = result.Message,
                        CooldownSeconds = result.CooldownSeconds
                    });
                }

                return BadRequest(new OtpResponseDto
                {
                    Success = false,
                    Message = result.Message
                });
            }

            return Ok(new OtpResponseDto
            {
                Success = true,
                Message = result.Message,
                CooldownSeconds = result.CooldownSeconds,
                ExpiresInMinutes = result.ExpiresInMinutes,
                DevOtp = result.DevOtp
            });
        }

        /// <summary>
        /// Xác thực mã OTP đã gửi qua Email
        /// </summary>
        [HttpPost("verify-registration-otp")]
        public async Task<ActionResult<OtpResponseDto>> VerifyRegistrationOtp([FromBody] VerifyOtpRequestDto dto)
        {
            if (!ModelState.IsValid)
            {
                return BadRequest(new OtpResponseDto
                {
                    Success = false,
                    Message = "Dữ liệu không hợp lệ."
                });
            }

            var result = await _otpService.VerifyRegistrationOtpAsync(dto.Email, dto.Otp);

            if (!result.Success)
            {
                return BadRequest(new OtpResponseDto
                {
                    Success = false,
                    Message = result.Message,
                    RemainingAttempts = result.RemainingAttempts
                });
            }

            return Ok(new OtpResponseDto
            {
                Success = true,
                Message = result.Message,
                VerificationToken = result.VerificationToken
            });
        }
    }
}
