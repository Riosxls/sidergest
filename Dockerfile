FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY Ebt.sln ./
COPY src/Ebt.Core/Ebt.Core.csproj src/Ebt.Core/
COPY src/Ebt.Api/Ebt.Api.csproj src/Ebt.Api/
COPY src/Ebt.DbfImport/Ebt.DbfImport.csproj src/Ebt.DbfImport/
RUN dotnet restore src/Ebt.Api/Ebt.Api.csproj && dotnet restore src/Ebt.DbfImport/Ebt.DbfImport.csproj
COPY src/ src/
RUN dotnet publish src/Ebt.Api/Ebt.Api.csproj -c Release -o /out/api --no-restore \
 && dotnet publish src/Ebt.DbfImport/Ebt.DbfImport.csproj -c Release -o /out/import --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS api
WORKDIR /app
COPY --from=build /out/api .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER app
ENTRYPOINT ["dotnet", "Ebt.Api.dll"]

FROM mcr.microsoft.com/dotnet/runtime:8.0 AS dbf-import
WORKDIR /app
COPY --from=build /out/import .
USER app
ENTRYPOINT ["dotnet", "Ebt.DbfImport.dll"]
