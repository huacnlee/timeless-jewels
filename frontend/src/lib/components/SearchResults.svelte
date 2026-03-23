<script lang="ts">
  import { _ } from 'svelte-i18n';
  import type { SearchResults, SearchWithSeed } from '../skill_tree';
  import { openTrade, TRADE_BATCH_SIZE } from '../skill_tree';
  import SearchResult from './SearchResult.svelte';
  import VirtualList from 'svelte-tiny-virtual-list';

  export let searchResults: SearchResults;
  export let highlight: (newSeed: number, passives: number[]) => void;
  export let groupResults = true;
  export let jewel: number;
  export let conqueror: string;
  export let platform: string;
  export let league: string;

  const computeSize = (r: SearchWithSeed) =>
    8 + 48 + r.skills.reduce((o, s) => o + 32 + Object.keys(s.stats).length * 24, 0);

  let expandedGroup: string | number = '';
</script>

{#if groupResults}
  <div class="flex flex-col overflow-auto">
    {#each Object.keys(searchResults.grouped)
      .map((x) => parseInt(x))
      .sort((a, b) => a - b)
      .reverse() as k}
      <button
        class="text-sm w-full py-1.5 px-3 bg-neutral-500/30 rounded flex flex-row items-center justify-between mb-1.5"
        on:click={() => (expandedGroup = expandedGroup === k ? '' : k)}>
        <span class="text-gray-200">
          {$_('matches', { values: { count: k } })}
          <span class="text-gray-400 ml-1">[{searchResults.grouped[k].length}]</span>
        </span>
        <div class="flex items-center gap-2">
          {#if expandedGroup !== k}
            <span class="text-xs text-amber-400/70 font-mono">
              {searchResults.grouped[k].slice(0, 5).map(r => r.seed).join(' · ')}{searchResults.grouped[k].length > 5 ? ' …' : ''}
            </span>
          {/if}
          <button
            class="text-xs px-2 py-0.5 rounded border border-blue-500/50 text-blue-400 hover:bg-blue-500/20 transition-colors"
            on:click|stopPropagation={() => openTrade(jewel, conqueror, searchResults.grouped[k].slice(0, TRADE_BATCH_SIZE), platform, league)}>
            {$_('Trade')}
          </button>
          <svg
            class="w-4 h-4 text-gray-400 transition-transform {expandedGroup === k ? 'rotate-180' : ''}"
            viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
          </svg>
        </div>
      </button>

      {#if expandedGroup === k}
        <div class="flex flex-col overflow-auto min-h-[200px] mb-2">
          <VirtualList
            height="auto"
            overscanCount={10}
            itemCount={searchResults.grouped[k].length}
            itemSize={searchResults.grouped[k].map(computeSize)}>
            <div slot="item" let:index let:style {style}>
              <SearchResult set={searchResults.grouped[k][index]} {highlight} {jewel} {conqueror} {platform} {league} />
            </div>
          </VirtualList>
        </div>
      {/if}
    {/each}
  </div>
{:else}
  <div class="mt-4 flex flex-col overflow-auto">
    <VirtualList
      height="auto"
      overscanCount={15}
      itemCount={searchResults.raw.length}
      itemSize={searchResults.raw.map(computeSize)}>
      <div slot="item" let:index let:style {style}>
        <SearchResult set={searchResults.raw[index]} {highlight} {jewel} {conqueror} {platform} {league} />
      </div>
    </VirtualList>
  </div>
{/if}
