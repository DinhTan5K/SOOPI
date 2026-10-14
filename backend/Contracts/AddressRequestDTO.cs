namespace SoopiFoodBE.Contracts;

public sealed record AddressRequest(
    string Label,
    string RecipientName,
    string Phone,
    string FullAddress,
    string? Note,
    bool IsDefault);
