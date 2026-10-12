namespace SoopiFoodBE.Contracts;

public sealed record OpeningHourResponse(
    Guid Id,
    Guid RestaurantId,
    byte DayOfWeek,
    TimeOnly OpensAt,
    TimeOnly ClosesAt,
    bool IsClosed);
