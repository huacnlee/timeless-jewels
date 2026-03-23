<script lang="ts">
  import { _ } from 'svelte-i18n';

  export let leagues: { value: string; label: string }[];
  export let platforms: { value: string; label: string }[];
  export let league: { value: string; label: string };
  export let platform: { value: string; label: string };
  export let results: boolean;
  export let onLeagueChange: () => void;
  export let onPlatformChange: () => void;

  let open = false;
  let activeSubmenu: string | null = null;

  const currentLocale = typeof localStorage !== 'undefined' ? (localStorage.getItem('locale') ?? 'en') : 'en';

  const selectLocale = (locale: string) => {
    localStorage.setItem('locale', locale);
    location.reload();
  };

  const setPlatform = (p: { value: string; label: string }) => {
    platform = p;
    onPlatformChange();
    activeSubmenu = null;
  };

  const setLeague = (l: { value: string; label: string }) => {
    league = l;
    onLeagueChange();
    activeSubmenu = null;
  };

  const clickOutside = (node: HTMLElement) => {
    const handle = (e: MouseEvent) => {
      if (!node.contains(e.target as Node)) {
        open = false;
        activeSubmenu = null;
      }
    };
    document.addEventListener('mousedown', handle, true);
    return { destroy: () => document.removeEventListener('mousedown', handle, true) };
  };

  const toggleSubmenu = (name: string) => {
    activeSubmenu = activeSubmenu === name ? null : name;
  };
</script>

<div class="relative" use:clickOutside>
  <button
    class="px-3 py-1 rounded bg-neutral-100/20 hover:bg-neutral-100/30 text-sm"
    on:click={() => {
      open = !open;
      activeSubmenu = null;
    }}>
    ⚙
  </button>

  {#if open}
    <div
      class="absolute right-0 top-full mt-1 bg-neutral-900 border border-white/10 rounded-lg shadow-2xl z-50 w-52 py-1"
      on:mousedown|stopPropagation>

      {#if results}
        <!-- Platform -->
        <div class="relative">
          <button
            class="w-full px-3 py-1.5 text-sm flex items-center justify-between hover:bg-white/5 transition-colors {activeSubmenu === 'platform' ? 'bg-white/5' : ''}"
            on:click={() => toggleSubmenu('platform')}>
            <span class="text-gray-300">{$_('Platform')}</span>
            <span class="flex items-center gap-1.5 text-gray-500 text-xs">
              {platform.label}
              <span>›</span>
            </span>
          </button>
          {#if activeSubmenu === 'platform'}
            <div class="absolute right-full top-0 mr-1 bg-neutral-900 border border-white/10 rounded-lg shadow-2xl w-32 py-1">
              {#each platforms as p}
                <button
                  class="w-full px-3 py-1.5 text-sm text-left flex items-center justify-between hover:bg-white/5 transition-colors {platform.value === p.value ? 'text-orange-400' : 'text-gray-300'}"
                  on:click={() => setPlatform(p)}>
                  {p.label}
                  {#if platform.value === p.value}<span>✓</span>{/if}
                </button>
              {/each}
            </div>
          {/if}
        </div>

        <!-- League -->
        <div class="relative">
          <button
            class="w-full px-3 py-1.5 text-sm flex items-center justify-between hover:bg-white/5 transition-colors {activeSubmenu === 'league' ? 'bg-white/5' : ''}"
            on:click={() => toggleSubmenu('league')}>
            <span class="text-gray-300">{$_('League')}</span>
            <span class="flex items-center gap-1.5 text-gray-500 text-xs">
              {league?.label ?? '…'}
              <span>›</span>
            </span>
          </button>
          {#if activeSubmenu === 'league'}
            <div class="absolute right-full top-0 mr-1 bg-neutral-900 border border-white/10 rounded-lg shadow-2xl w-44 py-1 max-h-60 overflow-y-auto">
              {#each leagues as l}
                <button
                  class="w-full px-3 py-1.5 text-sm text-left flex items-center justify-between hover:bg-white/5 transition-colors {league?.value === l.value ? 'text-orange-400' : 'text-gray-300'}"
                  on:click={() => setLeague(l)}>
                  {l.label}
                  {#if league?.value === l.value}<span>✓</span>{/if}
                </button>
              {/each}
            </div>
          {/if}
        </div>
      {/if}

      <div class="border-t border-white/10 my-1" />

      <!-- Language -->
      <div class="relative">
        <button
          class="w-full px-3 py-1.5 text-sm flex items-center justify-between hover:bg-white/5 transition-colors {activeSubmenu === 'language' ? 'bg-white/5' : ''}"
          on:click={() => toggleSubmenu('language')}>
          <span class="text-gray-300">{$_('Language')}</span>
          <span class="flex items-center gap-1.5 text-gray-500 text-xs">
            {currentLocale === 'zh' ? '中文' : 'EN'}
            <span>›</span>
          </span>
        </button>
        {#if activeSubmenu === 'language'}
          <div class="absolute right-full bottom-0 mr-1 bg-neutral-900 border border-white/10 rounded-lg shadow-2xl w-28 py-1">
            {#each [{ v: 'en', l: 'EN' }, { v: 'zh', l: '中文' }] as loc}
              <button
                class="w-full px-3 py-1.5 text-sm text-left flex items-center justify-between hover:bg-white/5 transition-colors {currentLocale === loc.v ? 'text-orange-400' : 'text-gray-300'}"
                on:click={() => selectLocale(loc.v)}>
                {loc.l}
                {#if currentLocale === loc.v}<span>✓</span>{/if}
              </button>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>
