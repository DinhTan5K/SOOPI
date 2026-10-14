using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Soopi.Backend.Models.Entities
{
    [Table("user_addresses")]
    public class UserAddress
    {
        [Key]
        [Column("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [MaxLength(128)]
        [Column("firebase_uid")]
        public string FirebaseUid { get; set; } = string.Empty;

        [Column("user_id")]
        public Guid? UserId { get; set; }

        [ForeignKey("UserId")]
        public User? User { get; set; }

        [MaxLength(50)]
        [Column("label")]
        public string Label { get; set; } = "Nhà riêng";

        [Required]
        [MaxLength(100)]
        [Column("recipient_name")]
        public string RecipientName { get; set; } = string.Empty;

        [Required]
        [MaxLength(20)]
        [Column("phone_number")]
        public string PhoneNumber { get; set; } = string.Empty;

        [Required]
        [MaxLength(500)]
        [Column("full_address")]
        public string FullAddress { get; set; } = string.Empty;

        [MaxLength(255)]
        [Column("note")]
        public string? Note { get; set; }

        [Column("is_default")]
        public bool IsDefault { get; set; } = false;

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }
    }
}
