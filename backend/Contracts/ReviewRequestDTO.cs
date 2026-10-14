namespace SoopiFoodBE.Contracts;

public sealed record ReviewRequest(
    byte RestaurantRating,
    byte? ShipperRating,
    string Comment);
