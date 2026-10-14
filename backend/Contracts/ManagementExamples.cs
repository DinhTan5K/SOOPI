using Microsoft.OpenApi.Any;
using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace SoopiFoodBE.Contracts;

public sealed class ManagementExamples : IOperationFilter
{
    public void Apply(OpenApiOperation operation, OperationFilterContext context)
    {
        var path = context.ApiDescription.RelativePath ?? "";
        if (!path.StartsWith("api/merchant") && !path.StartsWith("api/admin")) return;
        var name = context.MethodInfo.Name;
        var example = name switch
        {
            "Create" or "Update" => new OpenApiObject {
                ["name"] = new OpenApiString("Bếp Soopi"), ["description"] = new OpenApiString("Cơm và đồ uống"),
                ["phone"] = new OpenApiString("0901234567"), ["address"] = new OpenApiString("12 Nguyễn Văn Bảo"),
                ["city"] = new OpenApiString("Hồ Chí Minh"), ["latitude"] = new OpenApiDouble(10.822), ["longitude"] = new OpenApiDouble(106.688) },
            "CreateCategory" or "UpdateCategory" => new OpenApiObject {
                ["name"] = new OpenApiString("Món chính"), ["sortOrder"] = new OpenApiInteger(0) },
            "CreateItem" or "UpdateItem" => new OpenApiObject {
                ["categoryId"] = new OpenApiString("00000000-0000-0000-0000-000000000000"),
                ["name"] = new OpenApiString("Cơm gà"), ["description"] = new OpenApiString("Cơm gà và rau"),
                ["price"] = new OpenApiInteger(45000), ["isAvailable"] = new OpenApiBoolean(true) },
            "Operation" => new OpenApiObject { ["isActive"] = new OpenApiBoolean(true), ["isAcceptingOrders"] = new OpenApiBoolean(true) },
            "Hours" => new OpenApiObject { ["opensAt"] = new OpenApiString("08:00:00"), ["closesAt"] = new OpenApiString("22:00:00"), ["isClosed"] = new OpenApiBoolean(false) },
            "Availability" => new OpenApiObject { ["isAvailable"] = new OpenApiBoolean(false) },
            "Reject" => new OpenApiObject { ["reason"] = new OpenApiString("Vui lòng bổ sung địa chỉ đầy đủ.") },
            "LockRestaurant" or "LockUser" => new OpenApiObject { ["locked"] = new OpenApiBoolean(true), ["reason"] = new OpenApiString("Cần xác minh thông tin.") },
            _ => null
        };
        if (example is not null && operation.RequestBody?.Content.TryGetValue("application/json", out var content) == true)
            content.Example = example;
        operation.Responses.TryAdd("401", new OpenApiResponse { Description = "Missing or invalid Firebase ID token." });
        operation.Responses.TryAdd("403", new OpenApiResponse { Description = "Locked account/restaurant or insufficient permissions." });
        operation.Responses.TryAdd("404", new OpenApiResponse { Description = "Resource not found or belongs to another account." });
        operation.Responses.TryAdd("409", new OpenApiResponse { Description = "Invalid state transition or concurrent update; reload before retrying." });
    }
}
