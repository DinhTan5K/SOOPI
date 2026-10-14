namespace SoopiFoodBE.Contracts;

public sealed record CartLineRequest(Guid MenuItemId, int Quantity, string Note);
