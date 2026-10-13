using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Soopi.Backend.Models.DTOs;
using Soopi.Backend.Services;

namespace Soopi.Backend.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UserController : ControllerBase
    {
        private readonly IUserService _userService;
        private readonly ILogger<UserController> _logger;

        public UserController(IUserService userService, ILogger<UserController> logger)
        {
            _userService = userService;
            _logger = logger;
        }

        /// <summary>
        /// Lấy Firebase UID từ JWT Token hoặc Dev Header
        /// </summary>
        private (string uid, string email, string? name, string? photo) GetUserClaims()
        {
            var uid = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                   ?? User.FindFirst("user_id")?.Value
                   ?? User.FindFirst("sub")?.Value;

            var email = User.FindFirst(ClaimTypes.Email)?.Value
                     ?? User.FindFirst("email")?.Value;

            var name = User.FindFirst("name")?.Value
                    ?? User.FindFirst(ClaimTypes.Name)?.Value;

            var photo = User.FindFirst("picture")?.Value;

            if (string.IsNullOrEmpty(uid) && Request.Headers.TryGetValue("X-Firebase-Uid", out var fUid))
            {
                uid = fUid.ToString();
            }

            if (Request.Headers.TryGetValue("X-Firebase-Email", out var fEmail) && !string.IsNullOrEmpty(fEmail))
            {
                email = fEmail.ToString();
            }

            if (Request.Headers.TryGetValue("X-Firebase-Name", out var fName) && !string.IsNullOrEmpty(fName))
            {
                name = Uri.UnescapeDataString(fName.ToString());
            }

            // Hỗ trợ Swagger test nhanh khi chưa đăng nhập Firebase (nếu có header X-Dev-Uid)
            if (string.IsNullOrEmpty(uid) && Request.Headers.TryGetValue("X-Dev-Uid", out var devUid))
            {
                uid = devUid.ToString();
                email ??= $"{uid}@soopi.vn";
                name ??= "Developer Test";
            }

            return (uid ?? string.Empty, email ?? "user@soopi.vn", name, photo);
        }

        /// <summary>
        /// GET /api/user/profile - Lấy thông tin hồ sơ người dùng
        /// </summary>
        [HttpGet("profile")]
        public async Task<ActionResult<UserProfileDto>> GetProfile()
        {
            var (uid, email, name, photo) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Không xác thực được danh tính người dùng. Vui lòng cung cấp Bearer token hợp lệ." });
            }

            try
            {
                var profile = await _userService.GetOrCreateUserProfileAsync(uid, email, name, photo);
                return Ok(profile);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi khi lấy thông tin hồ sơ cho uid: {Uid}", uid);
                return StatusCode(500, new { message = "Lỗi máy chủ nội bộ", detail = ex.Message });
            }
        }

        /// <summary>
        /// PUT /api/user/profile - Cập nhật thông tin hồ sơ
        /// </summary>
        [HttpPut("profile")]
        public async Task<ActionResult<UserProfileDto>> UpdateProfile([FromBody] UpdateProfileDto dto)
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            try
            {
                var updated = await _userService.UpdateUserProfileAsync(uid, dto);
                return Ok(updated);
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "Không tìm thấy hồ sơ người dùng." });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi khi cập nhật hồ sơ cho uid: {Uid}", uid);
                return StatusCode(500, new { message = "Cập nhật hồ sơ thất bại", detail = ex.Message });
            }
        }

        /// <summary>
        /// GET /api/user/addresses - Lấy danh sách địa chỉ nhận hàng
        /// </summary>
        [HttpGet("addresses")]
        public async Task<ActionResult<List<UserAddressDto>>> GetAddresses()
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            var addresses = await _userService.GetUserAddressesAsync(uid);
            return Ok(addresses);
        }

        /// <summary>
        /// GET /api/user/addresses/{id} - Lấy chi tiết địa chỉ
        /// </summary>
        [HttpGet("addresses/{id}")]
        public async Task<ActionResult<UserAddressDto>> GetAddressById(Guid id)
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            var address = await _userService.GetUserAddressByIdAsync(id, uid);
            if (address == null)
            {
                return NotFound(new { message = "Không tìm thấy địa chỉ." });
            }

            return Ok(address);
        }

        /// <summary>
        /// POST /api/user/addresses - Thêm địa chỉ mới
        /// </summary>
        [HttpPost("addresses")]
        public async Task<ActionResult<UserAddressDto>> CreateAddress([FromBody] CreateOrUpdateAddressDto dto)
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            var created = await _userService.CreateUserAddressAsync(uid, dto);
            return CreatedAtAction(nameof(GetAddressById), new { id = created.Id }, created);
        }

        /// <summary>
        /// PUT /api/user/addresses/{id} - Cập nhật địa chỉ
        /// </summary>
        [HttpPut("addresses/{id}")]
        public async Task<ActionResult<UserAddressDto>> UpdateAddress(Guid id, [FromBody] CreateOrUpdateAddressDto dto)
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            var updated = await _userService.UpdateUserAddressAsync(id, uid, dto);
            if (updated == null)
            {
                return NotFound(new { message = "Không tìm thấy địa chỉ cần sửa." });
            }

            return Ok(updated);
        }

        /// <summary>
        /// DELETE /api/user/addresses/{id} - Xóa địa chỉ
        /// </summary>
        [HttpDelete("addresses/{id}")]
        public async Task<IActionResult> DeleteAddress(Guid id)
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            var success = await _userService.DeleteUserAddressAsync(id, uid);
            if (!success)
            {
                return NotFound(new { message = "Không tìm thấy địa chỉ cần xóa." });
            }

            return NoContent();
        }

        /// <summary>
        /// PATCH /api/user/addresses/{id}/set-default - Đặt làm địa chỉ mặc định
        /// </summary>
        [HttpPatch("addresses/{id}/set-default")]
        public async Task<IActionResult> SetDefaultAddress(Guid id)
        {
            var (uid, _, _, _) = GetUserClaims();
            if (string.IsNullOrEmpty(uid))
            {
                return Unauthorized(new { message = "Chưa đăng nhập." });
            }

            var success = await _userService.SetDefaultAddressAsync(id, uid);
            if (!success)
            {
                return NotFound(new { message = "Không tìm thấy địa chỉ." });
            }

            return Ok(new { message = "Đã đặt làm địa chỉ mặc định thành công." });
        }
    }
}
