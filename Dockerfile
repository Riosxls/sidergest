FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:de4fe90a98845d75910b9769662465c84de1a934665c431279d1382b2bddc02b AS build
WORKDIR /src
COPY Ebt.sln ./
COPY src/Ebt.Core/Ebt.Core.csproj src/Ebt.Core/
COPY src/Ebt.Api/Ebt.Api.csproj src/Ebt.Api/
COPY src/Ebt.DbfImport/Ebt.DbfImport.csproj src/Ebt.DbfImport/
RUN dotnet restore src/Ebt.Api/Ebt.Api.csproj && dotnet restore src/Ebt.DbfImport/Ebt.DbfImport.csproj
COPY src/ src/
RUN dotnet publish src/Ebt.Api/Ebt.Api.csproj -c Release -o /out/api --no-restore \
 && dotnet publish src/Ebt.DbfImport/Ebt.DbfImport.csproj -c Release -o /out/import --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0@sha256:ea721098d6ea2894ff9bd8387821a1659d4765d6c014b8d648bb1da16f016f5a AS api
WORKDIR /app
COPY --from=build /out/api .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER app
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 CMD ["dotnet", "Ebt.Api.dll", "--healthcheck"]
ENTRYPOINT ["dotnet", "Ebt.Api.dll"]

FROM mcr.microsoft.com/dotnet/runtime:8.0@sha256:67e16b7d568208713e05db7f7bcc81827679a636222160bf57bb148acd23622e AS dbf-import
WORKDIR /app
COPY --from=build /out/import .
USER app
ENTRYPOINT ["dotnet", "Ebt.DbfImport.dll"]
