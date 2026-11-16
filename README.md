# Renewed-Weathersync — motor climático persistente da Forge Core

Esta versão usa o `pr_bridge`, configurações JSON e um painel administrativo baseado em `registerContext`. A entrada da Forge Core em **Configurações do servidor → Clima e horário** abre este painel e preserva o retorno ao menu pai.

## Menu principal

1. **Resumo atual**: perfil, relógio, estratégia selecionada/ativa, evento, clima e tempo restante.
2. **Previsões em execução**: evento atual, etapas internas, próxima seleção conhecida e ações forçadas.
3. **Eventos climáticos**: criação, renomeação, ordenação, probabilidade, mês, vento e climas internos.
4. **Configurações**: modo exclusivo, txAdmin, neve em dezembro, relógio, evento fixo e perfis.
5. **Reconstruir previsões**: única ação que descarta deliberadamente a posição persistida.

Eventos são exibidos como `1 - Nome`, `2 - Nome` etc. O número é derivado da ordem; o ID estável do evento não muda quando ele é renomeado ou movido.

## Quatro modos exclusivos

- **Clima diário fixo**: um evento ocupa as 24 horas do relógio do jogo. As etapas internas são divididas igualmente; quatro etapas mudam às 00:00, 06:00, 12:00 e 18:00. Na meia-noite começa o próximo evento ordenado.
- **Clima sequencial**: percorre eventos e etapas internas na ordem, usando a duração configurada de cada clima.
- **Clima dinâmico**: escolhe o próximo evento pelo peso de probabilidade e nunca embaralha as etapas internas. A próxima escolha é persistida quando se torna conhecida.
- **Clima fixo**: repete apenas o evento padrão selecionado e persiste também sua posição interna.

Trocar o modo não interrompe instantaneamente o clima atual. O novo modo entra na próxima transição válida. **Reconstruir previsões** força o reinício controlado do ciclo.

## Prioridade do relógio

1. **Tempo real**: usa a hora da máquina do servidor e ignora escala, hora inicial, congelamento e alteração manual.
2. **Relógio congelado**: quando o tempo real está desligado, mantém e persiste hora/minuto.
3. **Horário escalável**: define em segundos quanto dura cada minuto do jogo durante dia e noite.
4. **Velocidade padrão**: sem tempo real e sem escala, cada minuto do jogo dura 2 segundos.

Forçar a hora aceita hora, minuto e congelamento opcional. A ação é bloqueada com tempo real ativo e não é interpretada como uma virada natural de dia.

## Neve e chuva

**Neve em dezembro** força somente neve no chão. O evento e o tipo de clima continuam normais. Os antigos limites `rainAfterRestart` e `timeBetweenRain` foram removidos: chuva depende exclusivamente dos eventos, sua ordem e probabilidades.

## Perfis e backups

Os perfis permitem manter configurações como padrão anual, Natal, Páscoa ou Halloween:

```
data/
  profiles.json
  runtime.json
  profiles/
    padrao/
      profile.json
      time.json
      weather.json
```

O painel permite criar do perfil atual, criar limpo, duplicar, renomear, importar/exportar JSON, sobrescrever e excluir. A ativação possui dois modos:

- **Ativar e continuar**: retoma a última posição persistida daquele perfil.
- **Ativar reiniciando o ciclo**: começa no primeiro evento válido.

A troca valida os dois JSON antes da ativação. O perfil ativo e o estado de cada perfil ficam em `runtime.json`. Os arquivos `data/time.json` e `data/weather.json` continuam como espelho do perfil ativo para compatibilidade e inspeção.

## Persistência

Para cada perfil são guardados hora/minuto, modo ativo e pendente, evento, etapa interna, duração sorteada, tempo restante, posição diária, contador de ciclo e próxima escolha dinâmica conhecida. O estado é salvo periodicamente, nas ações críticas e ao parar o recurso.

A primeira inicialização da versão 3 migra os JSON antigos para o perfil `padrao` sem apagar a configuração original antes de validá-la.

## Idiomas e compatibilidade

Os menus e explicações existem em `pt-br`, `en-us`, `es` e `fr`. O recurso mantém os contratos de `qb-weathersync`, `cd_easytime`, adaptadores existentes e exports administrativos.

Comando administrativo: `/weather`. Permissão: ACE `command.weather`.