namespace SoopiFoodBE.Contracts;

public sealed record MenuCategoryResponse(
    Guid Id,
    Guid RestaurantId,
    string Name,
    int SortOrder,
    List<MenuItemResponse> Items);
