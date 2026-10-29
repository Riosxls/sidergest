# Emissão de NF-e

Base: `emissor-nf/nf-emission-analysis.md` (fluxo do NF.exe antigo).

## Como funciona

- Liga em `PUT /api/fiscal/settings` (`enabled: true`, exige dados do emitente completos). Desligado, tudo se comporta como antes (número de NF digitado à mão).
- **Venda (CFOP 5101)**: `POST /api/sales/deliveries/{id}/ship` sem `invoiceNumber`. Ordem dentro de uma transação: baixa o estoque de PA, monta e envia a NF, só então grava `FiscalDocument` e preenche `InvoiceNumber` da entrega. Rejeição da SEFAZ ou falta de preço desfaz tudo (estoque, número, nada gravado).
- **Remessa para industrialização (CFOP 5901)**: `POST /api/production/orders/{id}/operations/{seq}/outside-shipments` sem `invoiceNumber`, com `unitValue` (valor de referência por unidade). Sem impostos (ICMS CST 50, IPI CST 55 cEnq 108, PIS/COFINS 09), texto legal do CFOP, sem duplicata.
- Informar `invoiceNumber` manualmente continua valendo (NF emitida fora, contingência, transição).
- Numeração: `fiscal_settings.next_number` (começa em 2581), só avança com NF autorizada. Linha travada com `FOR UPDATE`, então emissões são serializadas.
- Preço: tabela `monthly_prices` (produto × cliente × CFOP × mês). Sem preço no mês, a emissão é bloqueada (422).
- Impostos: `tax_rules` (produto × cliente opcional × CFOP) → senão alíquotas do item do pedido → CSTs padrão do CFOP (`cfops`). CFOPs semeados: 5101, 5124, 5901, 5902, 5920, 5921.
- Duplicatas: prazo do pedido (ou do cliente). `0` = à vista.
- Cancelamento: `POST /api/fiscal/documents/{id}/cancel` `{reason (>=15 chars), password}` (senha do próprio usuário; papéis Admin/SalesManager). Bloqueia se: remessa 5901 já tem retorno, entrega já confirmada (venda), passou da janela (`cancelWindowHours`, padrão 24). Venda cancelada cancela a entrega e devolve o estoque.

## O que é STUB / não feito

| Item | Estado |
|---|---|
| Transmissão SEFAZ-SP | Cliente real escrito (`SefazSpClient`), **nunca rodou contra a SEFAZ**: testado só com respostas simuladas e certificado autoassinado. Padrão continua o stub (`StubSefazClient`, `simulated = true`; rejeição de teste com `#SEFAZ-REJEITAR#` nas observações). |
| Assinatura XMLDSig A1 | Feita (`NfeSigner`, RSA-SHA1, C14N, enveloped). Falta validar com o certificado real. |
| `NFeAutorizacao4` / `NFeRetAutorizacao4` / `NFeRecepcaoEvento4` | Feitos (SOAP 1.2, TLS com certificado de cliente, autorização síncrona, consulta de recibo, cancelamento 110111). Sem consulta de situação por chave. |
| DANFE (PDF), e-mail do XML ao cliente/contador | Não feito. O XML (sem assinatura/protocolo) está em `GET /api/fiscal/documents/{id}/xml`. |
| Validação XSD do layout 4.00 | Não feita; o XML segue a ordem do layout mas nunca foi validado contra o schema. |
| 5124/5902 (industrialização por encomenda) e 5920/5921 (embalagem) | Só semeados em `cfops`. Não há gatilho nem tela para emitir. Venda aceita outro CFOP via `ship.cfop`, mas nada vincula embalagem à entrega. |
| Devolução, NF complementar, CC-e, inutilização de numeração | Não feito. |
| Custo médio do Suprimentos (E53 NFCO) e abatimento no contas a pagar | Sem integração; não existe abatimento no AP, então não há esse bloqueio no cancelamento. |
| Nº da O.F. obrigatório na venda | Não imposto: itens atendidos do estoque não têm O.F. A O.F. entra em `infCpl` quando existe. |
| Telas Flutter | Não feitas (só API). |

## Premissas a confirmar com o contador

- Base do ICMS = mercadoria + frete; IPI entra na base apenas para cliente não contribuinte. Arredondamento por item, 2 casas.
- PIS 0,65% e COFINS 3% como padrão do CFOP 5101 (cumulativo); ajustar em `cfops`/`tax_rules` se o regime for não cumulativo.
- `indPres = 9`, `indFinal = 0`, pagamento `tPag 14` (duplicata) / `90` (sem pagamento).
- Emitente: preencher `fiscal_settings` (CNPJ, IE, endereço, código IBGE) antes de ligar. Ambiente começa em homologação.

## Ligar a SEFAZ real (SEFAZ-SP)

1. Certificado A1 (.pfx) do emitente no servidor da API (ex.: pasta montada no container, fora do git).
2. Configuração (variáveis de ambiente; a senha nunca vai em arquivo):
   - `Fiscal__Sefaz__Mode=Sp`
   - `Fiscal__Sefaz__CertificatePath=/certs/ebt.pfx`
   - `Fiscal__Sefaz__CertificatePassword=...`
3. Começar em **homologação** (`PUT /api/fiscal/settings` com `environment: Homologation`; endpoint `homologacao.nfe.fazenda.sp.gov.br`). Só trocar para `Production` depois de autorizar NFs de teste e conferir o XML com o contador.
4. A API recusa subir se o certificado não existir, não tiver chave privada ou estiver vencido.
5. Timeout/falha de rede na autorização: o resultado é desconhecido (a SEFAZ pode ter autorizado). O erro 502 traz a chave de acesso; conferir no portal antes de emitir de novo. Falta a consulta automática de situação por chave.
6. Com `Sp`, `doc.Xml` guarda o `nfeProc` (NFe assinada + protocolo), pronto para enviar ao cliente/contador.
