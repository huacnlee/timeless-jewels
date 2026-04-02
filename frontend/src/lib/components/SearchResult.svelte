<script lang="ts">
  import { _ } from 'svelte-i18n';
  import type { SearchWithSeed } from '../skill_tree';
  import { skillTree, translateStat, openTrade } from '../skill_tree';

  export let highlight: (newSeed: number, passives: number[]) => void;
  export let set: SearchWithSeed;
  export let jewel: number;
  export let conqueror: string;
  export let platform: string;
  export let league: string;
  export let selectedSeed: number = -1;

  let copied = false;
  const copySeed = () => {
    navigator.clipboard.writeText(String(set.seed));
    copied = true;
    setTimeout(() => (copied = false), 1500);
  };
</script>

<div
  class="my-1.5 border rounded px-3 py-2 flex flex-col cursor-pointer transition-colors
    {set.seed === selectedSeed
      ? 'border-amber-400/60 bg-amber-400/5'
      : 'border-white/10 hover:border-white/25'}"
  on:click={() => highlight(set.seed, set.skills.map((s) => s.passive))}>

  <div class="flex flex-row items-center justify-between mb-1.5">
    <span class="text-xs text-gray-500 flex items-center gap-1">
      {$_('Seed')}
      <span class="text-amber-400 font-mono">{set.seed}</span>
      <button
        class="inline-flex items-center text-gray-500 hover:text-amber-400 transition-colors"
        on:click|stopPropagation={copySeed}
        title="Copy seed">
        {#if copied}
          <svg class="w-3 h-3 text-green-400" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
          </svg>
        {:else}
          <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
            <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
          </svg>
        {/if}
      </button>
      · {$_('Weight').toLowerCase()} <span class="text-sky-400">{set.weight}</span>
    </span>
    <button
      class="text-xs px-2 py-0.5 rounded border border-blue-500/50 text-blue-400 hover:bg-blue-500/20 transition-colors"
      on:click|stopPropagation={() => openTrade(jewel, conqueror, [set], platform, league)}>
      {$_('Trade')}
    </button>
  </div>

  {#each set.skills as skill}
    <div class="mt-1">
      <span class="text-xs text-gray-400">{skillTree.nodes[skill.passive].name}</span>
      <ul class="mt-0.5 space-y-0.5">
        {#each Object.keys(skill.stats) as stat}
          <li class="text-sm text-gray-100 pl-3">{translateStat(stat, skill.stats[stat])}</li>
        {/each}
      </ul>
    </div>
  {/each}
</div>
