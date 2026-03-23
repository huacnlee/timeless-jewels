<script lang="ts">
  import { _ } from 'svelte-i18n';

  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { proxy } from 'comlink';
  import Select from 'svelte-select';
  import SearchResults from '../../lib/components/SearchResults.svelte';
  import SkillTree from '../../lib/components/SkillTree.svelte';
  import type { ReverseSearchConfig, StatConfig } from '../../lib/skill_tree';
  import { getAffectedNodes, openTrade, TRADE_BATCH_SIZE, skillTree, translateStat } from '../../lib/skill_tree';
  import type { Node } from '../../lib/skill_tree_types';
  import { calculator, data } from '../../lib/types';
  import { statValues } from '../../lib/values';
  import { syncWrap } from '../../lib/worker';
  import { onMount } from 'svelte';
  const currentLocale = typeof localStorage !== 'undefined' ? localStorage.getItem('locale') ?? 'en' : 'en';

  const searchParams = $page.url.searchParams;

  const jewels = Object.keys(data.TimelessJewels).map((k) => ({
    value: parseInt(k),
    label: $_(data.TimelessJewels[k])
  }));

  let selectedJewel = searchParams.has('jewel') ? jewels.find((j) => j.value == searchParams.get('jewel')) : undefined;

  $: conquerors = selectedJewel
    ? Object.keys(data.TimelessJewelConquerors[selectedJewel.value]).map((k) => ({
        value: k,
        label: $_(k)
      }))
    : [];

  let selectedConqueror = searchParams.has('conqueror')
    ? {
        value: searchParams.get('conqueror'),
        label: searchParams.get('conqueror')
      }
    : undefined;

  let seed: number = searchParams.has('seed') ? parseInt(searchParams.get('seed')) : 0;

  let circledNode: number | undefined = searchParams.has('location')
    ? parseInt(searchParams.get('location'))
    : undefined;

  $: affectedNodes = circledNode
    ? getAffectedNodes(skillTree.nodes[circledNode]).filter((n) => !n.isJewelSocket && !n.isMastery)
    : [];

  let disabled = new Set<number>();

  let prevCircledNodeForDefault: number | undefined = undefined;
  $: if (affectedNodes.length > 0 && circledNode !== prevCircledNodeForDefault) {
    const isInitialLoad = prevCircledNodeForDefault === undefined;
    prevCircledNodeForDefault = circledNode;
    if (!isInitialLoad || !searchParams.has('disabled')) {
      disabled.clear();
      affectedNodes.filter((n) => !n.isNotable).forEach((n) => disabled.add(n.skill));
      disabled = disabled;
    }
  }

  $: seedResults =
    !seed ||
    !selectedJewel ||
    !selectedConqueror ||
    Object.keys(data.TimelessJewelConquerors[selectedJewel.value]).indexOf(selectedConqueror.value) < 0
      ? []
      : affectedNodes
          .filter((n) => !!data.TreeToPassive[n.skill])
          .map((n) => ({
            node: n.skill,
            result: calculator.Calculate(
              data.TreeToPassive[n.skill].Index,
              seed,
              selectedJewel.value,
              selectedConqueror.value
            )
          }));

  let selectedStats: Record<number, StatConfig> = {};
  if (searchParams.has('stat')) {
    searchParams.getAll('stat').forEach((s) => {
      const nStat = parseInt(s);
      selectedStats[nStat] = {
        weight: 1,
        min: 0,
        id: nStat
      };
    });
  }

  let mode = searchParams.has('mode') ? searchParams.get('mode') : '';

  const updateUrl = () => {
    const url = new URL(window.location.origin + window.location.pathname);
    selectedJewel && url.searchParams.append('jewel', selectedJewel.value.toString());
    selectedConqueror && url.searchParams.append('conqueror', selectedConqueror.value);
    seed && url.searchParams.append('seed', seed.toString());
    circledNode && url.searchParams.append('location', circledNode.toString());
    mode && url.searchParams.append('mode', mode);
    disabled.forEach((d) => url.searchParams.append('disabled', d.toString()));

    Object.keys(selectedStats).forEach((s) => {
      url.searchParams.append('stat', s.toString());
    });

    goto(url.toString());
  };

  const setMode = (newMode: string) => {
    mode = newMode;
    updateUrl();
  };

  if (searchParams.has('disabled')) {
    searchParams.getAll('disabled').forEach((d) => {
      disabled.add(parseInt(d));
    });
  }

  const clickNode = (node: Node) => {
    if (node.isJewelSocket) {
      circledNode = node.skill;
      updateUrl();
    } else if (!node.isMastery) {
      if (disabled.has(node.skill)) {
        disabled.delete(node.skill);
      } else {
        disabled.add(node.skill);
      }
      // Re-assign to update svelte
      disabled = disabled;
      updateUrl();
    }
  };

  const allPossibleStats: { [key: string]: { [key: string]: number } } = JSON.parse(data.PossibleStats);

  $: availableStats = !selectedJewel ? [] : Object.keys(allPossibleStats[selectedJewel.value]);
  $: statItems = availableStats
    .map((statId) => {
      const id = parseInt(statId);
      return {
        label: translateStat(id),
        value: id
      };
    })
    .filter((s) => !(s.value in selectedStats));

  let statSelector: Select;
  const selectStat = (stat: CustomEvent) => {
    selectedStats[stat.detail.value] = {
      weight: 1,
      min: 0,
      id: stat.detail.value
    };
    selectedStats = selectedStats;
    statSelector.handleClear();
    updateUrl();
  };

  const removeStat = (id: number) => {
    delete selectedStats[id];
    // Re-assign to update svelte
    selectedStats = selectedStats;
    updateUrl();
  };

  const changeJewel = () => {
    selectedStats = {};
    updateUrl();
  };

  let results = false;
  let minTotalWeight = 0;
  let searching = false;
  let currentSeed = 0;
  let searchResults: SearchResults;
  let searchJewel = 1;
  let searchConqueror = '';
  let searchSnapshot: { jewel: number; conqueror: string; stats: StatConfig[]; minTotalWeight: number } | undefined;

  $: tradeBatches = searchResults
    ? Array.from({ length: Math.ceil(searchResults.raw.length / TRADE_BATCH_SIZE) }, (_u, i) =>
        searchResults.raw.slice(i * TRADE_BATCH_SIZE, (i + 1) * TRADE_BATCH_SIZE)
      )
    : [];

  let tradeBatchIndex = 0;
  $: if (searchResults) {
    tradeBatchIndex = 0;
  }
  const search = () => {
    if (!circledNode) {
      return;
    }

    searchJewel = selectedJewel.value;
    searchConqueror = selectedConqueror.value;
    searching = true;
    searchResults = undefined;

    const stats = Object.keys(selectedStats).map((stat) => selectedStats[stat]);
    searchSnapshot = { jewel: selectedJewel.value, conqueror: selectedConqueror.value, stats, minTotalWeight };

    const query: ReverseSearchConfig = {
      jewel: selectedJewel.value,
      conqueror: selectedConqueror.value,
      nodes: affectedNodes
        .filter((n) => !disabled.has(n.skill))
        .map((n) => data.TreeToPassive[n.skill])
        .filter((n) => !!n)
        .map((n) => n.Index),
      stats,
      minTotalWeight
    };

    syncWrap
      .search(
        query,
        proxy((s) => (currentSeed = s))
      )
      .then((result) => {
        searchResults = result;
        searching = false;
        results = true;
      });
  };

  let highlighted: number[] = [];
  const highlight = (newSeed: number, passives: number[]) => {
    seed = newSeed;
    highlighted = passives;
    updateUrl();
  };

  const selectAll = () => {
    disabled.clear();
    // Re-assign to update svelte
    disabled = disabled;
  };

  const selectAllNotables = () => {
    affectedNodes.forEach((n) => {
      if (n.isNotable) {
        disabled.delete(n.skill);
      } else {
        disabled.add(n.skill);
      }
    });
    disabled = disabled;
  };

  const selectAllPassives = () => {
    affectedNodes.forEach((n) => {
      if (!n.isNotable) {
        disabled.delete(n.skill);
      } else {
        disabled.add(n.skill);
      }
    });
    disabled = disabled;
  };

  const deselectAll = () => {
    affectedNodes.filter((n) => !n.isJewelSocket && !n.isMastery).forEach((n) => disabled.add(n.skill));
    // Re-assign to update svelte
    disabled = disabled;
  };

  let groupResults =
    localStorage.getItem('groupResults') === null ? true : localStorage.getItem('groupResults') === 'true';
  $: localStorage.setItem('groupResults', groupResults ? 'true' : 'false');

  type CombinedResult = {
    id: string;
    rawStat: string;
    stat: string;
    passives: number[];
  };

  export const colorKeys = {
    physical: '#c79d93',
    cast: '#b3f8fe',
    fire: '#ff9a77',
    cold: '#93d8ff',
    lightning: '#f8cb76',
    attack: '#da814d',
    life: '#c96e6e',
    chaos: '#d8a7d3',
    unique: '#af6025',
    critical: '#b2a7d6'
  };

  const colorMessage = (message: string): string => {
    Object.keys(colorKeys).forEach((key) => {
      const value = colorKeys[key];
      message = message.replace(
        new RegExp(`(${key}(?:$|\\s))|((?:^|\\s)${key})`, 'gi'),
        `<span style='color: ${value}; font-weight: bold'>$1$2</span>`
      );
    });

    return message;
  };

  const combineResults = (
    rawResults: { result: data.AlternatePassiveSkillInformation; node: number }[],
    withColors: boolean,
    only: 'notables' | 'passives' | 'all'
  ): CombinedResult[] => {
    const mappedStats: { [key: number]: number[] } = {};
    rawResults.forEach((r) => {
      if (skillTree.nodes[r.node].isKeystone) {
        return;
      }

      if (only !== 'all') {
        if (only === 'notables' && !skillTree.nodes[r.node].isNotable) {
          return;
        }

        if (only === 'passives' && skillTree.nodes[r.node].isNotable) {
          return;
        }
      }

      if (r.result.AlternatePassiveSkill && r.result.AlternatePassiveSkill.StatsKeys) {
        r.result.AlternatePassiveSkill.StatsKeys.forEach((key) => {
          mappedStats[key] = [...(mappedStats[key] || []), r.node];
        });
      }

      if (r.result.AlternatePassiveAdditionInformations) {
        r.result.AlternatePassiveAdditionInformations.forEach((info) => {
          if (info.AlternatePassiveAddition.StatsKeys) {
            info.AlternatePassiveAddition.StatsKeys.forEach((key) => {
              mappedStats[key] = [...(mappedStats[key] || []), r.node];
            });
          }
        });
      }
    });

    return Object.keys(mappedStats).map((statID) => {
      const translated = translateStat(parseInt(statID));
      return {
        stat: withColors ? colorMessage(translated) : translated,
        rawStat: translated,
        id: statID,
        passives: mappedStats[statID]
      };
    });
  };

  const sortCombined = (
    combinedResults: CombinedResult[],
    order: 'count' | 'alphabet' | 'rarity' | 'value'
  ): CombinedResult[] => {
    switch (order) {
      case 'alphabet':
        return combinedResults.sort((a, b) =>
          a.rawStat
            .replace(/[#+%]/gi, '')
            .trim()
            .toLowerCase()
            .localeCompare(b.rawStat.replace(/[#+%]/gi, '').trim().toLowerCase())
        );
      case 'count':
        return combinedResults.sort((a, b) => b.passives.length - a.passives.length);
      case 'rarity':
        return combinedResults.sort(
          (a, b) => allPossibleStats[selectedJewel.value][a.id] - allPossibleStats[selectedJewel.value][b.id]
        );
      case 'value':
        return combinedResults.sort((a, b) => {
          const aValue = statValues[a.id] || 0;
          const bValue = statValues[b.id] || 0;
          if (aValue != bValue) {
            return bValue - aValue;
          }
          return allPossibleStats[selectedJewel.value][a.id] - allPossibleStats[selectedJewel.value][b.id];
        });
    }

    return combinedResults;
  };

  const sortResults = [
    {
      label: $_('Count'),
      value: 'count'
    },
    {
      label: $_('Alphabetical'),
      value: 'alphabet'
    },
    {
      label: $_('Rarity'),
      value: 'rarity'
    },
    {
      label: $_('Value'),
      value: 'value'
    }
  ] as const;

  let sortOrder = sortResults.find((r) => r.value === (localStorage.getItem('sortOrder') || 'count'));
  $: localStorage.setItem('sortOrder', sortOrder.value);

  let colored = localStorage.getItem('colored') === null ? true : localStorage.getItem('colored') === 'true';
  $: localStorage.setItem('colored', colored ? 'true' : 'false');

  let split = localStorage.getItem('split') === null ? true : localStorage.getItem('split') === 'true';
  $: localStorage.setItem('split', split ? 'true' : 'false');

  const onPaste = (event: ClipboardEvent) => {
    if (event.type !== 'paste') {
      return;
    }

    const paste = (event.clipboardData || window.clipboardData).getData('text');
    const lines = paste.split('\n');

    if (lines.length < 14) {
      return;
    }

    const jewel = jewels.find((j) => j.label === lines[2]);
    if (!jewel) {
      return;
    }

    let newSeed: number | undefined;
    let conqueror: string | undefined;
    for (let i = 10; i < lines.length; i++) {
      conqueror = Object.keys(data.TimelessJewelConquerors[jewel.value]).find((k) => lines[i].indexOf(k) >= 0);
      if (conqueror) {
        const matches = /(\d+)/.exec(lines[i]);
        if (matches.length === 0) {
          continue;
        }

        newSeed = parseInt(matches[1]);
        break;
      }
    }

    if (!conqueror || !newSeed) {
      return;
    }

    results = false;
    mode = 'seed';
    seed = newSeed;
    selectedJewel = jewel;
    selectedConqueror = { label: conqueror, value: conqueror };
    updateUrl();
  };

  let collapsed = false;

  const platforms = [
    { value: 'PC', label: currentLocale === 'zh' ? '国际服' : 'PC' },
    { value: 'Tencent', label: currentLocale === 'zh' ? '国服' : 'Tencent' },
    { value: 'Xbox', label: 'Xbox' },
    { value: 'Playstation', label: 'PS' }
  ];

  let settingsOpen = false;

  let platform = platforms.find((p) => p.value === localStorage.getItem('platform')) || platforms[0];
  $: localStorage.setItem('platform', platform.value);

  let leagues: { value: string; label: string }[] = [];
  let league: { value: string; label: string } | undefined;
  const getLeagues = async () => {
    const response = await fetch('https://api.poe.watch/leagues');
    const responseJson = await response.json();
    leagues = responseJson.map((l: { name: string }) => ({ value: l.name, label: $_(l.name) }));
    league = leagues.find((l) => l.value === localStorage.getItem('league')) || leagues[0];
  };

  $: league && localStorage.setItem('league', league.value);

  onMount(() => {
    getLeagues();
  });
</script>

<svelte:window on:paste={onPaste} />

<SkillTree
  {clickNode}
  {circledNode}
  selectedJewel={selectedJewel?.value}
  selectedConqueror={selectedConqueror?.value}
  {highlighted}
  {seed}
  highlightJewels={!circledNode}
  disabled={[...disabled]}>
  {#if !collapsed}
    <div
      class="w-screen md:w-10/12 lg:w-2/3 xl:w-1/2 2xl:w-5/12 3xl:w-1/3 4xl:w-1/4 min-w-[820px] absolute top-0 left-0 bg-black/80 backdrop-blur-sm themed rounded-br-lg max-h-screen">
      <div class="p-4 gap-3 max-h-screen flex flex-col">
        <div class="flex flex-row items-center justify-between mb-2 gap-2">
          <div class="flex flex-row gap-2 items-center">
            <button
              class="mr-2 w-7 h-7 flex items-center justify-center rounded text-gray-400 hover:text-white hover:bg-white/10 transition-colors"
              title="折叠面板"
              on:click={() => (collapsed = true)}>
              <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" class="w-4 h-4">
                <rect x="2" y="3" width="16" height="14" rx="1.5" />
                <line x1="7" y1="3" x2="7" y2="17" />
              </svg>
            </button>
            <div class="flex flex-row text-sm border border-white/20 rounded overflow-hidden">
              <button
                class="px-3 py-1 transition-colors {!results ? 'bg-white/20 text-white' : 'text-gray-400'}"
                on:click={() => (results = false)}>
                {$_('Config')}
              </button>
              {#if searchResults}
                <button
                  class="px-3 py-1 transition-colors {results ? 'bg-white/20 text-white' : 'text-gray-400'}"
                  on:click={() => (results = true)}>
                  {$_('Results')}
                </button>
              {/if}
            </div>
          </div>

          <div class="relative text-xs">
            <button
              class="flex items-center gap-1 text-gray-400 hover:text-gray-200 transition-colors"
              on:click={() => (settingsOpen = !settingsOpen)}>
              <span class="text-gray-600">{$_('Platform')}:</span>
              {platform.label}
              <span class="text-gray-600 mx-0.5">·</span>
              <span class="text-gray-600">{$_('League')}:</span>
              {league?.label ?? '...'}
              <span class="text-gray-600 mx-0.5">·</span>
              {currentLocale === 'zh' ? '中文' : 'EN'}
              <svg
                class="w-3 h-3 text-gray-600 ml-0.5 transition-transform {settingsOpen ? 'rotate-180' : ''}"
                viewBox="0 0 20 20"
                fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
                  clip-rule="evenodd" />
              </svg>
            </button>

            {#if settingsOpen}
              <button class="fixed inset-0 z-10" on:click={() => (settingsOpen = false)} />
              <div
                class="absolute right-0 top-full mt-1 bg-neutral-950 border border-white/10 rounded shadow-xl z-20 p-3 min-w-[200px] flex flex-col gap-3">
                <div>
                  <p class="text-xs text-gray-500 mb-1.5">{$_('Platform')}</p>
                  <div class="flex gap-1 flex-wrap">
                    {#each platforms as p}
                      <button
                        class="text-xs px-2 py-0.5 rounded transition-colors {platform.value === p.value
                          ? 'bg-orange-600/60 text-white'
                          : 'bg-white/10 text-gray-400 hover:bg-white/20'}"
                        on:click={() => {
                          platform = p;
                          updateUrl();
                        }}>
                        {p.label}
                      </button>
                    {/each}
                  </div>
                </div>
                <div>
                  <p class="text-xs text-gray-500 mb-1.5">{$_('League')}</p>
                  <select
                    class="w-full cursor-pointer"
                    value={league?.value}
                    on:change={(e) => {
                      league = leagues.find((l) => l.value === e.currentTarget.value);
                      updateUrl();
                    }}>
                    {#each leagues as l}
                      <option value={l.value}>{l.label}</option>
                    {/each}
                  </select>
                </div>
                <div>
                  <p class="text-xs text-gray-500 mb-1.5">{$_('Language')}</p>
                  <div class="flex gap-1">
                    {#each [{ v: 'en', l: 'EN' }, { v: 'zh', l: '中文' }] as loc}
                      <button
                        class="text-xs px-2 py-0.5 rounded transition-colors {currentLocale === loc.v
                          ? 'bg-orange-600/60 text-white'
                          : 'bg-white/10 text-gray-400 hover:bg-white/20'}"
                        on:click={() => {
                          localStorage.setItem('locale', loc.v);
                          location.reload();
                        }}>
                        {loc.l}
                      </button>
                    {/each}
                  </div>
                </div>
              </div>
            {/if}
          </div>
        </div>

        {#if !results}
          <div class="grid grid-cols-2 gap-2">
            <div>
              <p class="text-xs text-gray-400 mb-1">{$_('Timeless Jewel')}</p>
              <Select items={jewels} bind:value={selectedJewel} on:change={changeJewel} />
            </div>
            <div>
              <p class="text-xs text-gray-400 mb-1">{$_('Conqueror')}</p>
              <Select items={conquerors} bind:value={selectedConqueror} on:change={updateUrl} />
            </div>
          </div>

          {#if selectedJewel}
            {#if selectedConqueror && Object.keys(data.TimelessJewelConquerors[selectedJewel.value]).indexOf(selectedConqueror.value) >= 0}
              <div class="mt-3 flex gap-4">
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="mode"
                    value="seed"
                    checked={mode === 'seed'}
                    on:change={() => setMode('seed')}
                    class="accent-orange-500"
                    style="width:auto;height:auto;padding:0;" />
                  <span class="text-sm {mode === 'seed' ? 'text-white' : 'text-gray-400'}">{$_('Enter Seed')}</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="mode"
                    value="stats"
                    checked={mode === 'stats'}
                    on:change={() => setMode('stats')}
                    class="accent-orange-500"
                    style="width:auto;height:auto;padding:0;" />
                  <span class="text-sm {mode === 'stats' ? 'text-white' : 'text-gray-400'}">{$_('Select Stats')}</span>
                </label>
              </div>

              {#if mode === 'seed'}
                <div class="mt-4">
                  <p class="text-xs text-gray-400 mb-1">{$_('Seed')}</p>
                  <input
                    type="number"
                    bind:value={seed}
                    on:blur={updateUrl}
                    min={data.TimelessJewelSeedRanges[selectedJewel.value].Min}
                    max={data.TimelessJewelSeedRanges[selectedJewel.value].Max} />
                  {#if seed < data.TimelessJewelSeedRanges[selectedJewel.value].Min || seed > data.TimelessJewelSeedRanges[selectedJewel.value].Max}
                    <div class="mt-2">
                      {$_('Seed must be between', {
                        values: {
                          min: data.TimelessJewelSeedRanges[selectedJewel.value].Min,
                          max: data.TimelessJewelSeedRanges[selectedJewel.value].Max
                        }
                      })}
                    </div>
                  {/if}
                </div>

                {#if seed >= data.TimelessJewelSeedRanges[selectedJewel.value].Min && seed <= data.TimelessJewelSeedRanges[selectedJewel.value].Max}
                  <div class="flex flex-row mt-4 items-end">
                    <div class="flex-grow">
                      <p class="text-xs text-gray-400 mb-1">{$_('Sort Order')}</p>
                      <Select items={sortResults} bind:value={sortOrder} />
                    </div>
                    <div class="ml-2">
                      <button
                        class="bg-neutral-500/20 p-2 px-4 rounded"
                        class:selected={colored}
                        on:click={() => (colored = !colored)}>
                        {$_('Colors')}
                      </button>
                    </div>
                    <div class="ml-2">
                      <button
                        class="bg-neutral-500/20 p-2 px-4 rounded"
                        class:selected={split}
                        on:click={() => (split = !split)}>
                        {$_('Split')}
                      </button>
                    </div>
                  </div>

                  {#if !split}
                    <ul class="mt-4 overflow-auto" class:rainbow={colored}>
                      {#each sortCombined(combineResults(seedResults, colored, 'all'), sortOrder.value) as r}
                        <li class="cursor-pointer" on:click={() => highlight(seed, r.passives)}>
                          <span class="font-bold" class:text-white={(statValues[r.id] || 0) < 3}
                            >({r.passives.length})</span>
                          <span class="text-white">{@html r.stat}</span>
                        </li>
                      {/each}
                    </ul>
                  {:else}
                    <div class="overflow-auto mt-4">
                      <p class="text-xs text-gray-400 mb-1">{$_('Notables')}</p>
                      <ul class="mt-1" class:rainbow={colored}>
                        {#each sortCombined(combineResults(seedResults, colored, 'notables'), sortOrder.value) as r}
                          <li class="cursor-pointer" on:click={() => highlight(seed, r.passives)}>
                            <span class="font-bold" class:text-white={(statValues[r.id] || 0) < 3}
                              >({r.passives.length})</span>
                            <span class="text-white">{@html r.stat}</span>
                          </li>
                        {/each}
                      </ul>

                      <p class="text-xs text-gray-400 mt-3 mb-1">{$_('Passives')}</p>
                      <ul class="mt-1" class:rainbow={colored}>
                        {#each sortCombined(combineResults(seedResults, colored, 'passives'), sortOrder.value) as r}
                          <li class="cursor-pointer" on:click={() => highlight(seed, r.passives)}>
                            <span class="font-bold" class:text-white={(statValues[r.id] || 0) < 3}
                              >({r.passives.length})</span>
                            <span class="text-white">{@html r.stat}</span>
                          </li>
                        {/each}
                      </ul>
                    </div>
                  {/if}
                {/if}
              {:else if mode === 'stats'}
                <div class="mt-3">
                  <p class="text-xs text-gray-400 mb-1">{$_('Add Stat')}</p>
                  <Select
                    items={statItems}
                    on:change={selectStat}
                    bind:this={statSelector}
                    placeholder={$_('Search or select stat')} />
                </div>
                {#if Object.keys(selectedStats).length > 0}
                  <div class="mt-3 flex flex-col gap-1.5 overflow-auto">
                    {#each Object.keys(selectedStats) as s}
                      <div class="flex items-center gap-5 border border-white/10 rounded p-4">
                        <span class="flex-1 text-xs text-gray-200 truncate">{translateStat(selectedStats[s].id)}</span>
                        <label class="shrink-0 flex items-center gap-1 text-xs text-gray-500">
                          {$_('Min')}
                          <input class="stat-input" type="number" min="0" bind:value={selectedStats[s].min} />
                        </label>
                        <label class="shrink-0 flex items-center gap-1 text-xs text-gray-500">
                          {$_('Weight')}
                          <input class="stat-input" type="number" min="0" bind:value={selectedStats[s].weight} />
                        </label>
                        <button
                          class="shrink-0 text-xs text-gray-500 hover:text-red-400 transition-colors"
                          on:click={() => removeStat(selectedStats[s].id)}>
                          {$_('Remove')}
                        </button>
                      </div>
                    {/each}
                  </div>
                  <div class="mt-2 flex items-center gap-2">
                    <span class="text-xs text-gray-400 min-w-fit">{$_('Min Total Weight')}</span>
                    <input class="w-24" type="number" min="0" bind:value={minTotalWeight} />
                  </div>
                  <div class="mt-3 border border-white/10 rounded p-4 flex flex-col gap-1.5">
                    <p class="text-xs text-gray-500">{$_('Skill Tree View')} — {$_('Select Stats')}</p>
                    <div class="flex flex-wrap gap-1.5">
                      <button
                        class="px-3 py-1 text-xs bg-blue-500/40 hover:bg-blue-500/60 rounded transition-colors"
                        on:click={selectAll}>{$_('Select All')}</button>
                      <button
                        class="px-3 py-1 text-xs bg-purple-500/40 hover:bg-purple-500/60 rounded transition-colors"
                        on:click={selectAllNotables}>{$_('Notables')}</button>
                      <button
                        class="px-3 py-1 text-xs bg-teal-500/40 hover:bg-teal-500/60 rounded transition-colors"
                        on:click={selectAllPassives}>{$_('Passives')}</button>
                      <button
                        class="ml-auto px-3 py-1 text-xs bg-red-500/40 hover:bg-red-500/60 rounded transition-colors"
                        on:click={deselectAll}>{$_('Deselect')}</button>
                    </div>
                  </div>
                  <button
                    class="mt-2 w-full py-2 text-sm bg-green-500/40 rounded disabled:opacity-40 transition-colors"
                    on:click={() => search()}
                    disabled={searching}>
                    {#if searching}
                      {currentSeed} / {data.TimelessJewelSeedRanges[selectedJewel.value].Max}
                    {:else}
                      {$_('Search')}
                    {/if}
                  </button>
                {/if}
              {/if}

              {#if !circledNode}
                <h2 class="mt-4">{$_('Click on a jewel socket')}</h2>
              {/if}
            {/if}
          {/if}
        {/if}

        {#if searchResults && results && searchSnapshot}
          <div class="border border-white/10 rounded-lg px-3 py-2 mb-2 flex flex-col gap-1.5">
            <div class="flex items-center justify-between">
              <span class="text-sm font-medium text-gray-200">
                {$_(data.TimelessJewels[searchSnapshot.jewel])} · {$_(searchSnapshot.conqueror)}
              </span>
              <div class="flex items-center gap-2">
                <span class="text-xs text-gray-500"
                  >{$_('results_count', { values: { count: searchResults.raw.length } })}</span>
                <button
                  class="px-2 py-0.5 text-xs rounded border transition-colors {groupResults
                    ? 'border-orange-400 text-orange-400'
                    : 'border-white/20 text-gray-400 hover:border-white/40'}"
                  on:click={() => (groupResults = !groupResults)}>
                  {$_('Grouped')}
                </button>
              </div>
            </div>
            {#if searchSnapshot.stats.length > 0 || searchSnapshot.minTotalWeight > 0}
              <div class="flex flex-wrap gap-1">
                {#each searchSnapshot.stats as stat}
                  <span class="text-xs bg-white/5 border border-white/10 rounded px-2 py-0.5 text-gray-300">
                    {translateStat(stat.id)}{stat.min > 0 ? ` ≥ ${stat.min}` : ''}
                  </span>
                {/each}
                {#if searchSnapshot.minTotalWeight > 0}
                  <span class="text-xs bg-white/5 border border-white/10 rounded px-2 py-0.5 text-gray-300">
                    {$_('Weight')} ≥ {searchSnapshot.minTotalWeight}
                  </span>
                {/if}
              </div>
            {/if}

            {#if tradeBatches.length > 0}
              <div class="flex items-center justify-between pt-0.5">
                <span class="text-xs text-gray-500">{$_('Trade')}</span>
                <div class="flex items-center gap-1">
                  {#if tradeBatches.length > 1}
                    <button
                      class="px-2 py-0.5 text-xs rounded border border-blue-500/50 text-blue-400 hover:bg-blue-500/20 disabled:opacity-30 transition-colors"
                      on:click={() => (tradeBatchIndex = Math.max(0, tradeBatchIndex - 1))}
                      disabled={tradeBatchIndex === 0}>‹</button>
                  {/if}
                  <button
                    class="px-3 py-0.5 text-xs rounded border border-blue-500/50 text-blue-400 hover:bg-blue-500/20 whitespace-nowrap transition-colors"
                    on:click={() =>
                      openTrade(
                        searchJewel,
                        searchConqueror,
                        tradeBatches[tradeBatchIndex],
                        platform.value,
                        league.value
                      )}>
                    {$_('Trade')}
                    {tradeBatchIndex * TRADE_BATCH_SIZE + 1}–{Math.min(
                      (tradeBatchIndex + 1) * TRADE_BATCH_SIZE,
                      searchResults.raw.length
                    )}
                  </button>
                  {#if tradeBatches.length > 1}
                    <button
                      class="px-2 py-0.5 text-xs rounded border border-blue-500/50 text-blue-400 hover:bg-blue-500/20 disabled:opacity-30 transition-colors"
                      on:click={() => (tradeBatchIndex = Math.min(tradeBatches.length - 1, tradeBatchIndex + 1))}
                      disabled={tradeBatchIndex === tradeBatches.length - 1}>›</button>
                  {/if}
                </div>
              </div>
            {/if}
          </div>

          <SearchResults
            {searchResults}
            {groupResults}
            {highlight}
            jewel={searchJewel}
            conqueror={searchConqueror}
            platform={platform.value}
            league={league.value} />
        {/if}
      </div>
    </div>
  {:else}
    <button
      class="absolute top-0 left-0 bg-black/70 backdrop-blur-sm rounded-br-lg p-2.5 text-gray-400 hover:text-white transition-colors"
      title="展开面板"
      on:click={() => (collapsed = false)}>
      <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" class="w-4 h-4">
        <rect x="2" y="3" width="16" height="14" rx="1.5" />
        <line x1="7" y1="3" x2="7" y2="17" />
      </svg>
    </button>
  {/if}

  <div class="text-orange-500 absolute bottom-0 right-0 m-2">
    <a href="https://github.com/Vilsol/timeless-jewels" target="_blank" rel="noopener">Source (Github)</a>
  </div>
</SkillTree>

<style lang="postcss">
  .stat-input {
    height: 22px;
    width: 60px;
    padding: 0 6px;
    font-size: 0.75rem;
    appearance: none;
  }

  .selection-button {
    @apply bg-neutral-500/20 p-2 px-4 flex-grow;
  }

  .selection-button:first-child {
    @apply rounded-l border-r-2 border-black;
  }

  .selection-button:last-child {
    @apply rounded-r;
  }

  .selected {
    @apply bg-neutral-100/20;
  }

  .grouped {
    @apply bg-pink-500/40 disabled:bg-pink-900/40;
  }

  .rainbow {
    animation: colorRotate 2s linear 0s infinite;
  }

  @keyframes colorRotate {
    from {
      color: hsl(0, 100%, 50%);
    }
    25% {
      color: hsl(90, 100%, 50%);
    }
    50% {
      color: hsl(180, 100%, 50%);
    }
    75% {
      color: hsl(270, 100%, 50%);
    }
    100% {
      color: hsl(359, 100%, 50%);
    }
  }
</style>
