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
</script>

<div
  class="my-1.5 border border-white/10 rounded px-3 py-2 flex flex-col cursor-pointer hover:border-white/25 transition-colors"
  on:click={() => highlight(set.seed, set.skills.map((s) => s.passive))}>

  <div class="flex flex-row items-center justify-between mb-1.5">
    <span class="text-xs text-gray-500">{$_('Seed')} <span class="text-amber-400 font-mono">{set.seed}</span> · {$_('Weight').toLowerCase()} <span class="text-sky-400">{set.weight}</span></span>
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
