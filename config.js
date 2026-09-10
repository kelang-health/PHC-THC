export const SUPABASE_URL = 'https://tgeezbwbrovfyjbeykrj.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_bw0sKPthqc6Sl9xU8fdVpA_p2sZ4-N2';

if (typeof window !== 'undefined') {
  import('./community-gis-v1818.mjs?v=1.8.18')
    .then(async ({ initCommunityGIS }) => {
      await initCommunityGIS(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initHouseRegistration } = await import('./community-house-registration-v1819.mjs?v=1.8.19');
      await initHouseRegistration(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMyHousesMobile } = await import('./my-houses-mobile-v1820.mjs?v=1.8.20');
      await initMyHousesMobile(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
    })
    .catch(error => console.error('Community GIS/house modules load failed', error));
}
