# Simulador de preço

Este documento explica, sem termos técnicos, como o Simulador de preço do MetaGest funciona, de onde vêm os números dele, o que ele
acerta, o que ele não sabe e como mantê-lo atualizado.

## 1. Para que serve

Quando chega um pedido de um tubo que a empresa nunca vendeu, ou que não está em nenhuma tabela de preços, a pergunta de sempre é:
**"quanto eu cobro por isso?"**

Antes, o fluxo era assim: alguém digitava as medidas na planilha de peso (a aba "Calculo peso Blank" do Plano Mestre), via o peso do tubo e
o dono decidia o preço de cabeça, pela experiência.

O simulador faz esse mesmo caminho dentro do sistema e acrescenta o que faltava: ele **olha o que a empresa já cobrou** por tubos
parecidos e mostra um preço de referência. Quem decide continua sendo uma pessoa. O simulador sugere, não impõe.

## 2. Onde encontrar

- **Tela própria:** Comercial > grupo "Vendas" > **Simulador de preço**. Também aparece na busca (Ctrl K) e pode ser colocado nas ações
  rápidas do Painel.
- **Dentro do orçamento e do pedido de venda:** ao adicionar um item, se o produto não tem preço na tabela do cliente, aparece o botão
  **"Sugerir preço"** embaixo do campo de preço. Ele abre o simulador já preenchido com as medidas do produto, o cliente e a quantidade.
  Ao clicar em **"Usar este preço"**, o valor vai direto para o campo.
- **Quem pode usar:** Admin, Vendas e Gerente Comercial. Quem só consulta não vê o simulador, porque ele mostra preços de clientes.
- **Quem pode importar o histórico:** só Admin e Gerente Comercial.

## 3. Como usar

Preencha:

| Campo | O que é |
|---|---|
| Forma | **Redondo** ou **Oblongo** (achatado, com as pontas arredondadas). Troca os campos de medida |
| Diâmetro externo (mm) | Tubo redondo: medida de fora do tubo |
| Largura e altura (mm) | Tubo oblongo: o lado maior e o lado menor, medidos por fora |
| Espessura (mm) | Espessura da parede |
| Comprimento (mm) | Comprimento da peça |
| Cliente (opcional) | Se informado, o simulador procura o que **esse cliente** já pagou |
| Quantidade (opcional) | Em peças. Serve para calcular o total |
| Acréscimo pela forma (%) | Só no oblongo. Percentual que você soma ao preço pela conformação (veja o item 4) |
| Especificação (opcional) | BK, NBK, EN 10305, NBR ou SAE. Faz diferença no preço (veja o item 5) |

Não existe botão de "calcular": o resultado se atualiza sozinho alguns instantes depois de você parar de digitar.

## 4. O que o simulador mostra

### Desenho do tubo
Ao lado dos campos há um **desenho do tubo** (o corte e a vista lateral) com uma linha de cota para cada medida: diâmetro (ou largura e altura, no oblongo), espessura da parede e comprimento. O valor digitado aparece em cada linha e **a medida do campo em que você está digitando fica destacada**, como no desenho de um cliente. No celular, o desenho aparece acima dos campos.

### Tubo oblongo
O peso é calculado com a **seção real do oblongo** (um retângulo com as pontas em meia-circunferência). Como o histórico de preços só tem tubos redondos, o simulador procura o preço do **tubo redondo de mesmo perímetro** (a mesma volta por fora e a mesma parede) e avisa isso na tela. Esse preço **não inclui a conformação** do oblongo: some o percentual no campo **Acréscimo pela forma**, e a sugestão, a faixa e o total já aparecem com ele.

### Peso
- **Peso líquido:** o peso do tubo pronto.
- **Peso bruto:** o peso líquido mais **2,8%**, que é a perda de material. É a mesma conta da planilha do Plano Mestre. Se o produto
  tiver um percentual de perda próprio no cadastro, ele é usado no lugar dos 2,8%.

### Sugestão de preço
- **Preço por kg** e **preço por peça** (o preço por peça é o preço por kg multiplicado pelo peso líquido).
- **Faixa:** o menor e o maior preço por kg entre as vendas usadas como referência. Mostra o quanto os preços variam.
- **Total para a quantidade** informada, quando houver.
- **Confiança (Alta, Média ou Baixa):** diz o quanto a sugestão é confiável.
  - **Alta:** existe uma venda praticamente igual (ou o mesmo cliente já comprou essa medida).
  - **Média:** existem vendas parecidas, mas não iguais.
  - **Baixa:** as vendas mais parecidas ainda são bem diferentes. Use só como ponto de partida.
- **Motivo:** uma frase explicando de onde veio o número, por exemplo "Mesmo preço cobrado de Formigari em 11/2025 para esta medida" ou
  "Baseado em 7 vendas parecidas dos últimos 24 meses". Se não houver nada parecido, o simulador avisa e pede para você digitar o preço.
- **Último preço do cliente:** se o cliente já comprou qualquer tubo, mostra o último preço que ele pagou, mesmo de outra medida.

### Vendas parecidas
Uma tabela com as vendas que serviram de base: data, cliente, medida, unidade, preço, preço por kg, especificação e de onde veio a
informação ("Histórico" ou "MetaGest"). As mais parecidas ficam em cima. Linhas do cliente escolhido e da mesma especificação aparecem
destacadas. É o jeito de **conferir o raciocínio**: se uma venda da lista não faz sentido para o seu caso, desconfie da sugestão.

## 5. Como a sugestão é calculada

A ideia é simples: **"tubos parecidos custam parecido"**. O simulador procura, no histórico, as vendas mais parecidas e tira uma média
delas. Os passos:

1. **Tudo vira preço por kg.** Algumas vendas são por kg e outras por peça. Para comparar, o preço por peça é dividido pelo peso da peça.
   Assim um tubo de 300 mm e um de 6 metros podem ser comparados.
2. **Mede o quanto cada venda se parece com o que você digitou.** A "distância" leva em conta o diâmetro (peso maior), a espessura e o
   comprimento (peso menor). Se as duas especificações são conhecidas e diferentes, a venda fica mais "longe".
3. **Pega as 7 vendas mais parecidas** dos últimos 24 meses.
4. **Tira uma média dando mais peso às mais parecidas.** Uma venda quase igual pesa muito mais que uma venda distante.
5. **Regra do cliente:** se o cliente informado já comprou uma medida muito próxima, vale o preço mais recente dele, porque na prática
   cada cliente tem o seu preço.

O limite de 24 meses existe para o preço não ficar contaminado por épocas muito antigas.

## 6. O que a análise dos dados mostrou

Antes de construir, os dados da empresa foram estudados. Estes foram os achados que moldaram o simulador:

- **O Plano Mestre não tem preços.** Ele é uma planilha de planejamento de produção (máquinas, matéria-prima, ordens de fabricação). A
  única parte ligada às medidas é a aba de cálculo de peso. Por isso os preços foram buscados em outro lugar (item 7).
- **Os preços são estáveis desde 2021.** Em torno de **R$ 23,50 por kg**, com a maior parte entre R$ 20 e R$ 31.
- **Tubos mais finos custam mais por kg.** Quanto menor o diâmetro, maior o preço por kg (exemplo: diâmetro 5 a 6 mm perto de R$ 27 a 28
  por kg; 8 a 10 mm perto de R$ 21 a 22; 14 mm perto de R$ 19,50). A espessura e o comprimento quase não mudam o preço por kg.
- **A especificação do material pesa bastante.** Preço mediano por kg desde 2023:

  | Especificação | Preço por kg |
  |---|---|
  | NBK (normalizado) | cerca de R$ 30,00 |
  | BK | cerca de R$ 22,70 |
  | SAE | cerca de R$ 20,30 |
  | EN 10305 | cerca de R$ 20,00 |
  | NBR 5599 | cerca de R$ 19,90 |

- **O preço depende do cliente.** Exemplos de preço mediano por kg desde 2023: Formigari cerca de R$ 20,30, Top Diesel cerca de R$ 31,08,
  NewPipe cerca de R$ 45,70. Por isso o simulador dá atenção especial ao cliente.
- **A maioria dos pedidos é repetição.** Em 2025 e 2026, cerca de 85% dos pedidos eram do mesmo cliente, mesma medida e mesmo preço de um
  pedido anterior. Nesses casos o simulador só precisa lembrar o último preço.
- **O que não ajudou:** a quantidade comprada e o número de passadas de trefila não melhoraram a previsão e ficaram de fora.

## 7. Fontes e dados coletados

O banco de dados do MetaGest hoje só tem registros de teste (10 linhas de orçamento, todas a cerca de R$ 23,70 por kg). Por isso o
histórico real foi buscado nas planilhas da empresa, todas dentro da pasta `EBT` (no computador do Italo:
`C:\Users\italo\Desktop\EBT`). Os arquivos foram **apenas lidos**: nenhuma planilha foi alterada.

### 7.1 Resumo

| Fonte | Arquivos | Abas / registros lidos | Aproveitado |
|---|---|---|---|
| Planilha mestre de pedidos | 1 arquivo, com 200 abas | 147 abas mensais com o formato de controle de pedidos; 6.960 linhas com preço | 4.817 vendas válidas, sem repetições entre meses |
| Pedidos Internos de Venda | 3.576 arquivos (um por pedido) | 3.576 pedidos lidos, cada um com a aba do pedido e a da ordem de fabricação | cerca de 3.400 pedidos válidos |
| Plano Mestre | 1 arquivo, com 23 abas | só a aba de cálculo de peso | fórmula do peso (sem preços) |
| Pedidos feitos no MetaGest | (banco de dados) | só os que não são de teste | entram sozinhos, sem importar |

Juntando as duas fontes de planilhas, são cerca de **8.200 linhas**. Depois de reunir as repetições (mesmo cliente, mesma medida e mesmo
preço, que aparecem em vários meses ou em vários pedidos), ficam **2.674 vendas únicas**, de **outubro de 2015 a novembro de 2026**,
das quais **1.393 têm a especificação do material**.

### 7.2 Planilha mestre de pedidos

- **Arquivo:** `Pedidos de Vendas\PEDIDO DE VENDAS Anos 24 & 26 - EBT e BST.xlsx`.
- **Conteúdo:** 200 abas. Uma aba por mês de controle de pedidos de clientes (de 2015 a 2026), mais abas de apoio (gráficos, compra de
  matéria-prima, cesta básica e outras). Foram usadas as **147 abas mensais** que têm as colunas de diâmetro, espessura, comprimento,
  unidade e valor unitário. A aba "Vendas Perdidas" foi examinada, mas **não** entrou no simulador.
- **O que foi coletado de cada linha:** data do pedido, número do pedido, cliente, descrição do material, diâmetro, espessura,
  comprimento, quantidade, unidade (kg ou peça) e valor unitário. Nas abas mais novas também existe o peso da peça e o preço por kg, que
  serviram para conferir as contas.
- **Limpeza:** foram descartadas linhas sem medida, sem preço, com espessura impossível (mais da metade do diâmetro) ou em unidades que
  não são kg nem peça. O mesmo pedido aparece em meses seguidos (enquanto estava aberto), então essas repetições foram reunidas.
- **Resultado:** 4.817 vendas válidas, de 2015 a 2026.

### 7.3 Pedidos Internos de Venda

- **Pasta:** `Pedidos de Vendas\PEDIDOS DE VENDAS  BST 25 & 26`, com **3.576 arquivos Excel**, um por pedido (por exemplo,
  `PEDIDO 04679-26 Formigari 12,70 X 1,50 X 869.xlsx`). Os pedidos vão de 2016 a 2026.
- **O que cada arquivo tem:** a aba "Pedido" (cliente, endereço, medidas do tubo, quantidade e unidade, especificação do material, data de
  entrega, preço de venda, ICMS, IPI, prazo de pagamento, valor total, assinatura e data) e a aba "OP" (matéria-prima, tubo primário e
  a lista de operações de fabricação).
- **O que o simulador usa:** data, cliente, diâmetro, espessura, comprimento, quantidade, unidade, preço e **especificação do material**
  (que a planilha mestre não tem).
- **O que foi lido, mas não ajudou a prever o preço:** prazo de pagamento, IPI, quantidade e número de passadas de trefila (extraído da
  lista de operações). Esses dados foram testados e **não** melhoraram a previsão, então ficaram de fora.
- **Aproveitamento:** cerca de **3.400 pedidos válidos** dos 3.576 arquivos. Os demais foram descartados por falta de dados ou porque o
  comprimento era "rolo" (bobina), sem medida em milímetros.
- **Sobreposição:** só cerca de **1 em cada 3** desses pedidos também aparece na planilha mestre. Por isso as duas fontes foram usadas
  juntas.

### 7.4 Plano Mestre

- **Arquivo:** `Plano Mestre.xls`, com 23 abas (máquinas, programação, necessidade de matéria-prima, ordens de fabricação, embalagem e
  outras).
- **O que foi usado:** apenas a aba **"Calculo peso Blank"**, para conferir a fórmula do peso (peso líquido e peso bruto com 2,8% de perda).
  O sistema já fazia a mesma conta do peso líquido.
- **O que foi descoberto:** o Plano Mestre **não tem nenhum preço**. É uma planilha de planejamento de produção.

### 7.5 Pedidos feitos no próprio MetaGest

Os pedidos de venda criados no sistema (que não sejam de teste) e que tenham tubo redondo com medidas e preço entram sozinhos como fonte
do simulador, sem importar nada. Com o tempo, o histórico das planilhas perde importância e o do sistema passa a ser a principal base.

## 8. O quanto dá para confiar

Foi feito um teste "para o passado": para cada pedido de 2025 e 2026, o simulador previu o preço usando **só o que existia antes daquele
pedido**, e a previsão foi comparada com o preço realmente cobrado.

- Para **clientes que repetem a mesma medida**, o preço é praticamente o último cobrado. É a grande maioria dos casos.
- Para **medidas que o cliente nunca comprou**, o erro típico ficou em cerca de **6%**. Em 9 de cada 10 casos, o erro ficou abaixo de
  cerca de 18% a 20%.
- Para comparar: usar a média geral dos preços erraria cerca de 12% de forma típica, e uma fórmula matemática simples cerca de 9%.

Ou seja: **a sugestão é um bom ponto de partida e costuma ficar perto do que a empresa cobraria**, mas não substitui o julgamento de quem
conhece o cliente e o momento do mercado.

## 9. Cuidados e limites

- **Reflete o que foi cobrado, não o que seria o ideal.** O simulador aprende com o passado. Se um preço antigo estava baixo, a
  sugestão herda isso. Ele não sabe de margem nem de custo.
- **Não sabe o preço atual da matéria-prima.** Se o aço subir ou cair de repente, o simulador só percebe depois que novos pedidos entrarem.
- **Só tubos redondos e oblongos.** Perfis retangulares e quadrados não entram por enquanto.
- **O preço do oblongo é uma aproximação.** Não existe histórico de oblongos: o preço é o do redondo equivalente e o acréscimo pela forma é decisão sua.
- **Não considera quantidade, prazo de pagamento, frete ou impostos.** O preço sugerido é o preço de venda por kg ou por peça, como nas
  planilhas.
- **Nome de cliente escrito de formas diferentes** (por exemplo "IKS" e "IKS - Indústria...") pode ser tratado como clientes diferentes. A
  comparação usa o começo do nome e algumas regras simples.
- **Pouco histórico para medidas muito raras.** Nesses casos a confiança vem como Baixa. Leia a tabela de vendas parecidas antes de usar.
- **Pedidos de teste não entram.** Registros marcados como teste são ignorados.
- **Preços de clientes são sigilosos.** Por isso o simulador é restrito a quem vende, e o arquivo gerado para importação nunca deve ser
  enviado ao GitHub nem compartilhado fora da empresa.

## 10. Como manter o histórico atualizado

Os pedidos novos do MetaGest entram sozinhos. As planilhas antigas só precisam ser importadas de novo quando você quiser incluir pedidos
que ainda estão só nelas (por exemplo, pedidos novos feitos nas planilhas de pedido interno).

1. Gerar o arquivo (leva cerca de um minuto; o Excel precisa estar instalado):
   ```
   powershell -File scripts\export-price-history.ps1
   ```
   Ele cria o arquivo `price-history.csv` na pasta do projeto.
2. No MetaGest: **Comercial > Simulador de preço > "Importar histórico (CSV)"** e escolher esse arquivo. É preciso ser Admin ou Gerente
   Comercial.
3. O sistema mostra quantas vendas foram lidas, importadas, atualizadas e ignoradas.

Pode importar quantas vezes quiser: uma venda que já existe não é duplicada, apenas recebe a data mais nova e a especificação, se ela
ainda não tinha. O histórico importado **não é apagado** pela limpeza de dados do sistema (ele é dado de referência, como a tabela de
preços) e volta junto com o backup do banco.

## 11. Ideias para o futuro

- Incluir perfis retangulares e quadrados.
- Guardar no histórico as vendas de tubos oblongos, para o simulador aprender o acréscimo pela forma.
- Mostrar a evolução do preço por kg ao longo do tempo para uma medida ou cliente.
- Unir nomes de cliente escritos de formas diferentes.
- Considerar o preço da matéria-prima do dia e a margem desejada.
- Guardar a quantidade de cada compra, para estudar descontos por volume.

## 12. Para quem for mexer no código

| O quê | Onde |
|---|---|
| Cálculo de peso (igual ao da planilha) | `src/Ebt.Core/Services/TubeWeight.cs` |
| Regra da sugestão (vizinhos mais próximos) | `src/Ebt.Core/Sales/PriceSuggestionService.cs` |
| Classificação da especificação (BK, NBK...) | `src/Ebt.Core/Sales/PriceSpec.cs` |
| Importação do CSV | `src/Ebt.Core/Sales/PriceHistoryImporter.cs` |
| Tabela do histórico | `src/Ebt.Core/Entities/PriceHistory.cs` (tabela `price_history`) |
| Endpoints (`/api/sales/price-suggestion`, `/api/sales/price-history/...`) | `src/Ebt.Api/Endpoints/PriceSuggestionEndpoints.cs` |
| Script que lê as planilhas | `scripts/export-price-history.ps1` |
| Tela | `clients/flutter/lib/screens/price_simulator.dart` |
| Testes | `tests/Ebt.Tests/PriceSuggestionTests.cs`, `clients/flutter/test/price_simulator_test.dart` |

Detalhes de operação (formato do CSV, regras de deduplicação) estão em `docs/OPERATIONS.md`.
