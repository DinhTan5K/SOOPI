namespace SoopiFoodBE.Contracts;

public sealed record MerchantReviewRow(Guid Id, Guid OrderId, string OrderCode,
    string CustomerName, byte RestaurantRating, string Comment, DateTime CreatedAt);

public sealed record MerchantReviewPage(IReadOnlyList<MerchantReviewRow> Items,
    int Total, int Page, int PageSize, double AverageRating);
