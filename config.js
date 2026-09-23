export const SUPABASE_URL = 'https://tgeezbwbrovfyjbeykrj.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_' + 'bw0sKPthqc6S' + 'l9xU8fdVpA_p2sZ4-N2';

if (typeof window !== 'undefined') {
  // All Cloud announcements and booking activities are paused by the operator.
  import('./community-gis-v1822.mjs?v=1.8.63&p=2035')
    .then(async ({ initCommunityGIS1822 }) => {
      await initCommunityGIS1822(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initHouseRegistration } = await import('./community-house-registration-v1819.mjs?v=1.8.20&p=2045');
      await initHouseRegistration(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMyHousesMobile } = await import('./my-houses-mobile-v1820.mjs?v=2.0.68&p=2068');
      await initMyHousesMobile(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMobileSpatialCards } = await import('./mobile-community-volunteer-cards-v1821.mjs?v=2.0.57&p=2057');
      await initMobileSpatialCards(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initCommunityWorkflow1822 } = await import('./community-workflow-v1822.mjs?v=2.0.69&p=2069');
      await initCommunityWorkflow1822(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMobileUIPolish1824 } = await import('./mobile-ui-polish-v1824.mjs?v=1.8.24b&p=2035');
      await initMobileUIPolish1824(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initVolunteerProfileRegistry1825 } = await import('./volunteer-profile-registry-v1825.mjs?v=2.0.77&p=2077');
      await initVolunteerProfileRegistry1825(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initTrainingDashboardV2077 } = await import('./training-dashboard-v2077.mjs?v=2.0.77&p=2077');
      await initTrainingDashboardV2077(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initInteractionFeedback1827 } = await import('./interaction-feedback-v1827.mjs?v=1.8.28');
      await initInteractionFeedback1827();
      const { initCareDashboard1860 } = await import('./care-dashboard-v1860.mjs?v=2.0.59&p=2059');
      await initCareDashboard1860(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initSystemAboutNote1829 } = await import('./system-about-note-v1829.mjs?v=2.0.57&p=2057');
      initSystemAboutNote1829();
      const { initCommunityHouseholdQuality1831 } = await import('./community-household-quality-v1831.mjs?v=2.0.77&p=2077');
      await initCommunityHouseholdQuality1831(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initPHCFiveFeatures190 } = await import('./phc-five-features-v190.mjs?v=2.0.101&p=2101');
      await initPHCFiveFeatures190(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initFieldWorkReportingV200 } = await import('./field-work-reporting-v200.mjs?v=2.0.59&p=2059');
      await initFieldWorkReportingV200(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
    })
    .catch(error => console.error('Community GIS/house/mobile workflow modules load failed', error));
}
