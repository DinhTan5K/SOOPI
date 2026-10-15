using System.ComponentModel.DataAnnotations;
namespace SoopiFoodBE.Contracts;

public sealed record RestaurantUpdate(
    [Required, StringLength(150)] string Name,
    [StringLength(1000)] string Description,
    [Required, StringLength(20)] string Phone,
    [Required, StringLength(500)] string Address,
    [Required, StringLength(100)] string City,
    bool IsActive,
    bool IsAcceptingOrders);
