namespace SoopiFoodBE.Contracts;

public sealed record OpeningHourRequest(
    TimeOnly OpensAt,
    TimeOnly ClosesAt,
    bool IsClosed);
