# Clima em cache — 03/10/2026

## Situação

Implementado e validado localmente; **aguarda homologação em FiveM**. Os arquivos ativos do Renewed-Weathersync e do NPWD Forge Weather não utilizam mais state bags para clima, tempo, blackout ou pausa local de sincronização. O motor de eventos, regiões e persistência JSON foi preservado.

## Contrato para outros recursos

Usar o PR Bridge, sem consultar chaves internas de cache ou acessar o provedor diretamente:

```lua
local ok, snapshot = pr_lib.weather.GetSnapshot()
if ok and snapshot.weather then
    local clock = snapshot.currentTime -- hour / minute
    local weather = snapshot.weather -- weather / splitRegions / regions
    local blackout = snapshot.blackOut
end
```

- Servidor e cliente: `GetSnapshot()` retorna `ok, dados` com `weather`, `currentTime`, `timeScale`, `freezeTime`, `isNight`, `blackOut`. As cópias retornadas não alteram o cache original.
- Servidor: `GetRegionalWeather(id)`, `GetWeeklyForecast()`, `GetState()` e controles existentes continuam disponíveis pelo bridge.
- Cliente: `GetCurrentRegion()`, `GetRegionFromCoords(coords)`, `GetRegionalWeather()` (região atual), `ToggleSync(boolean)`.
- Ambos: `OnChange(function(key, value) ... end)` assina o evento local do bridge; o identificador retornado pode ser passado a `RemoveEventHandler`.
- Nenhum retorno bem-sucedido é fabricado se o provedor estiver parado ou rejeitar a edição.

## Sincronização e desempenho

O cache `pr_lib.cache` mantém o estado dentro do contexto do recurso. Ele não replica automaticamente nem é consultado diretamente por consumidores externos. O servidor fornece snapshot inicial por callback do bridge e transmite mudanças explícitas com geração/revisão. Clientes rejeitam origem não servidor, revisões antigas e pacotes de gerações anteriores.

Relógio, escala, noite e congelamento são publicados numa transação. Valores iguais não geram transmissão. Blackout individual é direcionado ao jogador, vinculado à identidade do personagem e limpo na saída; uma resposta antiga de snapshot não sobrescreve um blackout recebido mais recentemente. A pausa de sincronização é local, sem publicação de estado de jogador.

A previsão mantém seus sete dias no servidor. Em 03/10/2026 os rótulos passaram a ser relativos: Hoje, Amanhã, Depois de amanhã e Daqui a 3–6 dias. O aplicativo mostra os quatro primeiros e o widget os três primeiros. Os rótulos vêm das traduções pt-br, en-us, es e fr; datas continuam como metadados e a lógica de projeção/mapas foi preservada.

## Recursos alterados

- Renewed-Weathersync: módulo compartilhado de cache, produtores/consumidores ativos e compatibilidades QB/CD/vSync.
- NPWD Forge Weather: leitura pelo bridge, definição de região pelo provedor e atualização pelo evento de cache.
- PR Bridge: adaptadores Renewed de cliente/servidor.
- Forge Core: painel sem fallback que gravava estados globais diretamente.
- Forge Garage: somente a leitura de horário usada no parquímetro; estados e lógica de veículos não foram migrados nesta etapa.

## Anormalidades encontradas

Corrigidas nesta integração:

1. Compatibilidade QB escrevia horário/congelamento fora do relógio autoritativo e podia perder a alteração no próximo tick.
2. Blackout individual era publicado, mas não aplicado no cliente.
3. Mudança de escala podia descongelar o relógio do cliente.
4. Export compatível CD não registrava sua função via `setCB`.
5. Fallbacks do bridge/painel podiam apresentar sucesso mesmo com provedor parado ou edição rejeitada.

Proteção adicional da migração: durante a troca de perfis, a publicação síncrona do relógio não permite que o observador do clima antigo sobrescreva o runtime recém-ativado. Cenário coberto por teste. Snapshot válido sem clima (eventos desabilitados) também encerra a hidratação, evitando consultas contínuas desnecessárias de todos os jogadores.

**Para análise posterior, sem mudanças nesta etapa:**

- Os seis arquivos sem carregamento/referências ativas em `legacy/` foram removidos em 03/10/2026, com autorização do responsável: `client/admin.lua`, `config/time.lua`, `config/weather.lua`, `server/time.lua`, `server/weather.lua` e `server/weatherbuilder.lua`. Eram o painel, configurações e motor antigos, substituídos pelos módulos ativos e JSON.
- O fallback do NPWD já usava temperaturas/ícones ilustrativos (ex.: 22 °C e céu limpo) quando não conseguia obter previsão real. Esse comportamento de apresentação foi preservado; recomenda-se decidir se o app deve mostrar indisponibilidade em vez de dados ilustrativos.
- A projeção semanal existente não é uma simulação integral das durações/probabilidades dos quatro modos. Foi preservada; uma reformulação requer decisão própria.
- Temperaturas do aplicativo são simuladas por tipo de clima, região e horário em `computeRegionTemps`/`getWeeklyForecast`; não são uma leitura nativa de temperatura ambiente do GTA.

## Testes locais

Três suítes Lua usam o código real com ambiente FiveM simulado:

- `tests/cache_transport_test.lua`: cópias, publicação atômica, snapshot tardio, blackout isolado, logout, origem/revisão/geração e corrida snapshot/pacote.
- `tests/engine_test.lua`: relógio, fronteiras diárias, quatro modos, regiões, previsão semanal, congelamento, ACL, compatibilidades e restauração do evento/etapa após reinício.
- `tests/client_app_test.lua`: natives simuladas, norte/sul, pausa/retomada, blackout, bridge, NPWD, painel Forge e provedor parado. Ler ou escrever state bags provoca falha deliberada no teste.

Validação: **31 arquivos Lua ativos/consumidores/testes/manifests** com `luac55.exe -p`. Nenhum teste em jogo, benchmark ou reinício de FXServer foi executado automaticamente. Nenhum JSON persistente ou banco real foi alterado pelos testes.

Revalidação dos rótulos/limpeza em 03/10/2026: sintaxe dos dois Lua alterados aprovada, três suítes Lua aprovadas (incluindo os sete rótulos e `dayShort` usado pelo widget), quatro catálogos JSON validados e build game do NPWD concluído. A checagem TypeScript completa apontou a declaração ausente de `window.invokeNative` em `src/utils/fetchNui.ts`, arquivo não alterado nesta etapa. O build também avisou sobre API CJS do Vite depreciada e bundle acima de 500 kB; não impediram a geração. Teste visual em FiveM permanece pendente.

## Homologação

Reiniciar o servidor para recarregar também os adaptadores do bridge nos consumidores. Verificar: dois jogadores em norte/sul, alteração de horário/perfil/modo pelo painel, pausa/retomada em interiores, blackout global e individual, previsão/mapa/widget do NPWD, entrada tardia e reinício do recurso preservando o runtime. Só marcar aprovado após confirmação do responsável.
