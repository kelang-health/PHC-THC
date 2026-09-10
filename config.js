export const SUPABASE_URL = 'https://tgeezbwbrovfyjbeykrj.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_' + 'bw0sKPthqc6S' + 'l9xU8fdVpA_p2sZ4-N2';

if (typeof window !== 'undefined') {
  import('./community-gis-v1822.mjs?v=1.8.22')
    .then(async ({ initCommunityGIS1822 }) => {
      await initCommunityGIS1822(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initHouseRegistration } = await import('./community-house-registration-v1819.mjs?v=1.8.19');
      await initHouseRegistration(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMyHousesMobile } = await import('./my-houses-mobile-v1820.mjs?v=1.8.20');
      await initMyHousesMobile(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMobileSpatialCards } = await import('./mobile-community-volunteer-cards-v1821.mjs?v=1.8.21b');
      await initMobileSpatialCards(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initCommunityWorkflow1822 } = await import('./community-workflow-v1822.mjs?v=1.8.22');
      await initCommunityWorkflow1822(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMobileUIPolish1824 } = await import('./mobile-ui-polish-v1824.mjs?v=1.8.24b');
      await initMobileUIPolish1824(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initVolunteerProfileRegistry1825 } = await import('./volunteer-profile-registry-v1825.mjs?v=1.8.25');
      await initVolunteerProfileRegistry1825(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
    })
    .catch(error => console.error('Community GIS/house/mobile workflow modules load failed', error));
}
