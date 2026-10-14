namespace SoopiFoodBE.Contracts;

public sealed record RestaurantUpdate(
    string Name,
    string Description,
    string Phone,
    string Address,
    string City,
    bool IsActive,
    bool IsAcceptingOrders);
