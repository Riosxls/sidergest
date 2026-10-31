# Schemas NF-e (layout 4.00)

Official SEFAZ XSDs, pacote **PL_009 (layout 4.00)**; the `leiauteNFe_v4.00.xsd` header lists changes up to `PL_009p_NT2024_003_v101`.
Vendored (copied unchanged) from the `nfephp-org/sped-nfe` mirror, folder `schemes/PL_009_V4`, state of 2025-06-02. They are embedded in
`Ebt.Core.dll` and used by `NfeSchema` to validate every NF-e (and the inutilização / consulta XML) before it is sent to SEFAZ.

Files: `nfe_v4.00.xsd`, `leiauteNFe_v4.00.xsd`, `tiposBasico_v4.00.xsd`, `xmldsig-core-schema_v1.01.xsd` (NF-e);
`inutNFe_v4.00.xsd`, `leiauteInutNFe_v4.00.xsd`, `retInutNFe_v4.00.xsd` (inutilização);
`consSitNFe_v4.00.xsd`, `leiauteConsSitNFe_v4.00.xsd`, `retConsSitNFe_v4.00.xsd` (consulta de protocolo).

To update: download the new package from the Portal Nacional da NF-e (Documentos > Esquemas XML), replace the files here, run the tests, and
update this note. Validation happens on the unsigned XML, so the optional `Signature` element is not exercised.
