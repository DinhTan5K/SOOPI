using System.ComponentModel.DataAnnotations;

namespace Soopi.Backend.Models.DTOs
{
    public class UserAddressDto
    {
        public Guid Id { get; set; }
        public string FirebaseUid { get; set; } = string.Empty;
        public string Label { get; set; } = "Nhà riêng";
        public string RecipientName { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public string FullAddress { get; set; } = string.Empty;
        public string? Note { get; set; }
        public bool IsDefault { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class CreateOrUpdateAddressDto
    {
        public string? Label { get; set; } = "Nhà riêng";

        [Required(ErrorMessage = "Tên người nhận không được để trống")]
        public string RecipientName { get; set; } = string.Empty;

        [Required(ErrorMessage = "Số điện thoại không được để trống")]
        public string PhoneNumber { get; set; } = string.Empty;

        [Required(ErrorMessage = "Địa chỉ chi tiết không được để trống")]
        public string FullAddress { get; set; } = string.Empty;

        public string? Note { get; set; }

        public bool IsDefault { get; set; } = false;
    }
}
