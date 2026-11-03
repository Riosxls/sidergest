# Emissão de NF-e

Base: `emissor-nf/nf-emission-analysis.md` (fluxo do NF.exe antigo).

## Como funciona

- Liga em `PUT /api/fiscal/settings` (`enabled: true`, exige dados do emitente completos). Desligado, tudo se comporta como antes (número de NF digitado à mão).
- **Venda (CFOP 5101)**: `POST /api/sales/deliveries/{id}/ship` sem `invoiceNumber`. Ordem: baixa o estoque de PA (transação do chamador), valida o XML contra o XSD, reserva o número e grava a NF como **Pending** (conexão própria, já confirmada), chama a SEFAZ, grava o resultado (também em conexão própria) e só então liga itens e entrega na transação do chamador. Rejeição da SEFAZ ou falta de preço desfaz estoque e entrega; o número volta para a fila quando ninguém pegou um número posterior (senão a linha fica `Rejected`, buraco para inutilizar).
- **Remessa para industrialização (CFOP 5901)**: `POST /api/production/orders/{id}/operations/{seq}/outside-shipments` sem `invoiceNumber`, com `unitValue` (valor de referência por unidade). Sem impostos (ICMS CST 50, IPI CST 55 cEnq 108, PIS/COFINS 09), texto legal do CFOP, sem duplicata.
- Informar `invoiceNumber` manualmente continua valendo (NF emitida fora, contingência, transição).
- Numeração: `fiscal_settings.next_number` (começa em 2581). O número é reservado (avança) junto com o registro `Pending`, com a linha travada por `FOR UPDATE` só durante essa transação curta; **a trava nunca fica presa durante a chamada à SEFAZ**.
- Situações: `Pending` (número reservado, resposta da SEFAZ desconhecida ou em andamento), `Authorized`, `Cancelled`, `Rejected` (SEFAZ recusou e o número não pôde voltar). Timeout/erro de rede deixa a NF `Pending` (erro 502 com a chave).
- Conciliação: `POST /api/fiscal/documents/{id}/reconcile` e `POST /api/fiscal/documents/reconcile` (todas as pendentes), `?minAgeMinutes=10` (padrão) poupa NFs recém-enviadas. Consulta a chave (`NFeConsultaProtocolo4`): autorizada vira `Authorized` (avisa quando ficou sem entrega/remessa vinculada: cancele dentro da janela); inexistente na SEFAZ devolve o número ou deixa `Rejected`; cancelada fora do sistema vira `Cancelled`. Permissão `fiscal-cancel`. Na tela da NF: "Conciliar com a SEFAZ".
- Inutilização: `POST /api/fiscal/inutilizations` `{series?, from, to, reason (>=15), password}` (permissão `fiscal-cancel`; senha do usuário). Só números já emitidos (abaixo de `next_number`) e sem NF viva (`Rejected` ou sem registro); grava `fiscal_inutilizations` (auditada). Lista: `GET /api/fiscal/inutilizations`. Flutter: botão "Inutilizar numeração" na lista de notas.
- Layout: todo XML é validado contra o XSD oficial 4.00 (`Schemas/`, ver README lá) antes de reservar número e de enviar; falha vira 422 com o caminho do elemento. A inutilização também é validada.
- DANFE: gerado no cliente Flutter (`lib/reports/danfe_doc.dart`) a partir da NF gravada, botão PDF na tela da NF. Faixa "SEM VALOR FISCAL" em homologação/simulada, "CANCELADA" quando for o caso.
- Preço: o preço da linha do pedido é o padrão; `monthly_prices` (produto × cliente × CFOP × mês) o substitui. Quando os dois existem e diferem, vale o mensal e o aviso fica em `fiscal_documents.warnings` e no histórico da entrega (`nf-price-warning`). Sem preço mensal, emite com o do pedido; só bloqueia (422) quando não há nenhum.
- Duplicidade (SEFAZ 204/539): o número **não** volta para a fila. A NF fica `Pending` com `keyLookupRequired`; "Conciliar" consulta a chave: autorizada vira `Authorized`, desconhecida vira `Rejected` (o número continua usado por outra NF: acertar o próximo número ou inutilizar). As demais rejeições seguem devolvendo o número (exceto 110/301/302/303, denegadas).
- Uma entrega só pode ter uma NF viva: índice único parcial `ux_fiscal_documents_live_delivery` em `fiscal_documents(delivery_id)` para `Pending`/`Authorized`. `CancelAsync`, devolução e CC-e travam a linha da NF (`FOR UPDATE`) antes de chamar a SEFAZ.
- Transporte: `pesoL` (soma do peso líquido dos produtos, quando todos têm) e `pesoB` (peso bruto da expedição, nunca abaixo do líquido); transportadora com CNPJ/IE/endereço/UF vem do cadastro `fiscal_carriers` (`/api/fiscal/carriers`, casa pelo nome digitado na entrega); a UF da placa é a do cadastro (UF da placa, senão UF da transportadora) e só cai na UF do emitente quando nada foi cadastrado.
- Impostos: `tax_rules` (produto × cliente opcional × CFOP) → senão alíquotas do item do pedido → CSTs padrão do CFOP (`cfops`). CFOPs semeados: 5101, 5124, 5901, 5902, 5920, 5921.
- Duplicatas: prazo do pedido (ou do cliente). `0` = à vista.
- Cancelamento: `POST /api/fiscal/documents/{id}/cancel` `{reason (>=15 chars), password}` (senha do próprio usuário; papéis Admin/SalesManager). Bloqueia se: remessa 5901 já tem retorno, entrega já confirmada (venda), passou da janela (`cancelWindowHours`, padrão 24). Venda cancelada cancela a entrega e devolve o estoque.

## O que é STUB / não feito

| Item | Estado |
|---|---|
| Transmissão SEFAZ-SP | Cliente real escrito (`SefazSpClient`), **nunca rodou contra a SEFAZ**: testado só com respostas simuladas e certificado autoassinado. Padrão continua o stub (`StubSefazClient`, `simulated = true`; rejeição de teste com `#SEFAZ-REJEITAR#` nas observações). |
| Assinatura XMLDSig A1 | Feita (`NfeSigner`, RSA-SHA1, C14N, enveloped). Falta validar com o certificado real. |
| `NFeAutorizacao4` / `NFeRetAutorizacao4` / `NFeRecepcaoEvento4` / `NFeConsultaProtocolo4` / `NFeInutilizacao4` | Feitos no `SefazSpClient` (SOAP 1.2, TLS com certificado de cliente, autorização síncrona, consulta de recibo, cancelamento 110111, consulta por chave, inutilização). **Todos só testados com respostas simuladas.** O stub guarda o que autorizou para responder à consulta por chave e simula timeout (`#SEFAZ-TIMEOUT#`, `#SEFAZ-TIMEOUT-AUTORIZADA#`). |
| Emissão pending-first, conciliação, inutilização | Feitas (ver acima), com testes de integração contra o stub. Falta rodar em homologação real. Conciliação manual (botão/endpoint) e agendada: `FiscalReconcileService` consulta a cada 10 min as NFs `Pending` com mais de 5 min (desliga com `Fiscal:Reconcile:Enabled=false`). NF autorizada pela SEFAZ após resposta perdida fica sem entrega vinculada (aviso na conciliação). |
| DANFE (PDF) | Feito no Flutter. Layout próprio, não validado contra o manual do DANFE (NT) nem contra leitores de código de barras; QR Code não se aplica (NF-e modelo 55). E-mail do XML ao cliente/contador: não feito. O XML (sem assinatura/protocolo no stub) está em `GET /api/fiscal/documents/{id}/xml`. |
| Validação XSD do layout 4.00 | Feita (`NfeSchema`, pacote PL_009 em `Schemas/`). Valida o XML sem assinatura (um `Signature` de mentira cobre a exigência do schema). Regras de negócio da SEFAZ (cStat 2xx) não são cobertas pelo XSD. |
| Testes de impostos | `NfeTaxTests`: casos de exemplo (ICMS/IPI/PIS/COFINS, arredondamento por item a 2 casas, frete, CST 20/50, CFOP sem imposto) e a saída do `NfeXml`. **Os valores esperados são casos de exemplo calculados à mão; o contador precisa aprovar regras e valores.** |
| 5124/5902 (industrialização por encomenda) e 5920/5921 (embalagem) | Só semeados em `cfops`. Não há gatilho nem tela para emitir. Venda aceita outro CFOP via `ship.cfop`, mas nada vincula embalagem à entrega. |
| Devolução (finNFe 4), CC-e (110110) | Feitas, **só contra o stub e respostas simuladas**. O evento CC-e (`descEvento`, `xCorrecao`, `xCondUso`, Id `ID110110`+chave+nSeq de 2 dígitos) foi escrito pela NT 2011.004 e **não foi validado contra a SEFAZ nem contra XSD** (o pacote em `Schemas/` não traz o `envEvento`). Ver "Devolução e CC-e". |
| NF complementar (finNFe 2) | Não feito (exige regra própria de diferença de valor/imposto sem quantidade). |
| Custo médio do Suprimentos (E53 NFCO) e abatimento no contas a pagar | Sem integração; não existe abatimento no AP, então não há esse bloqueio no cancelamento. |
| Nº da O.F. obrigatório na venda | Não imposto: itens atendidos do estoque não têm O.F. A O.F. entra em `infCpl` quando existe. |
| Telas Flutter | Lista e detalhe da NF (conciliar, cancelar, devolver, carta de correção, DANFE), inutilização na lista e configurações do emitente. O cadastro de transportadoras só existe na API (`/api/fiscal/carriers`), sem tela. |

## Devolução e CC-e

- **Devolução de venda**: `POST /api/fiscal/documents/{id}/return` `{lines:[{itemId, quantity}], locationId, reason}` (permissão `fiscal-emit`) sobre uma NF de venda `Authorized`. É uma NF de **entrada própria** emitida pela EBT (`tpNF 0`, `finNFe 4`, `NFref/refNFe` com a chave da original), CFOP **1202** (mesma UF) ou **2202** (outra UF), semeados em `cfops` com `Kind = Return`. Quantidade limitada ao saldo ainda não devolvido (`FiscalService.ReturnedByLineAsync`, conta devoluções `Authorized`/`Pending`); preço, alíquotas e CSTs vêm das linhas da NF original (CST do IPI de saída 50..55/99 vira 00..05/49; PIS/COFINS mantêm o CST original); frete proporcional. Sem duplicatas (`tPag 90`).
- Estoque: na mesma transação da NF, movimento `CustomerReturn` no local escolhido, com o mesmo lote da expedição quando conhecido (limitado ao que cada lote enviou, descontando devoluções anteriores). Se a SEFAZ recusar, nada muda. Cancelar a NF de devolução (rota `/cancel`, fora de `SalesService`) estorna o movimento. A NF original não pode ser cancelada enquanto houver devolução viva.
- Histórico: evento `nf-return` na entrega e no pedido (`sales_events`) e linha em `audit_log` (`FiscalDocument`/`Return`). Documento: `referenced_document_id`, `referenced_access_key`, `stock_document_id`; linha: `referenced_line_id`.
- Pendências de devolução: NF de devolução cuja resposta se perdeu fica `Pending` sem linhas nem estoque; a conciliação a autoriza e avisa "sem entrega vinculada" (cancele-a). **A confirmar com o contador**: CSTs de PIS/COFINS na entrada, base do ICMS na devolução e se o cliente contribuinte deve emitir a própria NF de saída (nesse caso a EBT só registra a entrada de terceiros, não feito).
- **CC-e**: `POST /api/fiscal/documents/{id}/correction` `{text}` (`fiscal-emit`) em NF `Authorized`: texto de 15 a 1000 caracteres (espaços colapsados), sequência 1..20 por NF (`fiscal_events`, índice único + check), evento assinado com `NfeSigner.SignEvent` e enviado por `ISefazClient.CorrectAsync` (`NFeRecepcaoEvento4`, como o cancelamento; status 135/155 = registrado). O stub sempre autoriza, salvo `#SEFAZ-REJEITAR#` no texto. Aparece em `GET document` (`events`) e na tela da NF; não vai no DANFE. Um timeout deixa a sequência desconhecida: a próxima tentativa pode voltar 573 (duplicidade de evento).

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
5. Timeout/falha de rede na autorização: o resultado é desconhecido (a SEFAZ pode ter autorizado). A NF fica `Pending` e o erro 502 traz a chave de acesso; use "Conciliar com a SEFAZ" (consulta por chave) antes de emitir de novo.
6. Com `Sp`, `doc.Xml` guarda o `nfeProc` (NFe assinada + protocolo), pronto para enviar ao cliente/contador.
