export const SUPABASE_URL = 'https://tgeezbwbrovfyjbeykrj.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_' + 'bw0sKPthqc6S' + 'l9xU8fdVpA_p2sZ4-N2';

if (typeof window !== 'undefined') {
  // All Cloud announcements and booking activities are paused by the operator.
  import('./community-gis-v1822.mjs?v=2.0.138-gps-permission&p=2178')
    .then(async ({ initCommunityGIS1822 }) => {
      await initCommunityGIS1822(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initHouseRegistration } = await import('./community-house-registration-v1819.mjs?v=2.0.138-gps-permission&p=2178');
      await initHouseRegistration(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMyHousesMobile } = await import('./my-houses-mobile-v1820.mjs?v=2.0.138-gps-permission&p=2178');
      await initMyHousesMobile(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMobileSpatialCards } = await import('./mobile-community-volunteer-cards-v1821.mjs?v=2.0.133-mobile-map-focus&p=2171');
      await initMobileSpatialCards(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initCommunityWorkflow1822 } = await import('./community-workflow-v1822.mjs?v=2.0.141-stay-on-house-after-save&p=2181');
      await initCommunityWorkflow1822(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initMobileUIPolish1824 } = await import('./mobile-ui-polish-v1824.mjs?v=2.0.133-mobile-map-focus&p=2171');
      await initMobileUIPolish1824(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initVolunteerProfileRegistry1825 } = await import('./volunteer-profile-registry-v1825.mjs?v=2.0.133-mobile-map-focus&p=2171');
      await initVolunteerProfileRegistry1825(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initTrainingDashboardV2077 } = await import('./training-dashboard-v2077.mjs?v=2.0.133-mobile-map-focus&p=2171');
      await initTrainingDashboardV2077(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initInteractionFeedback1827 } = await import('./interaction-feedback-v1827.mjs?v=1.8.28');
      await initInteractionFeedback1827();
      const { initCareDashboard1860 } = await import('./care-dashboard-v1860.mjs?v=2.0.135-followup-v2195&p=2195');
      await initCareDashboard1860(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initSystemAboutNote1829 } = await import('./system-about-note-v1829.mjs?v=2.0.124&p=2124');
      initSystemAboutNote1829();
      const { initCommunityHouseholdQuality1831 } = await import('./community-household-quality-v1831.mjs?v=2.0.154-house-register-review&p=2202');
      await initCommunityHouseholdQuality1831(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initPHCFiveFeatures190 } = await import('./phc-five-features-v190.mjs?v=2.0.156-elderly-prior-ncd&p=2206');
      await initPHCFiveFeatures190(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initFieldWorkReportingV200 } = await import('./field-work-reporting-v200.mjs?v=2.0.59&p=2059');
      await initFieldWorkReportingV200(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      const { initCoordinateAuditV2132 } = await import('./coordinate-audit-v2132.mjs?v=2.0.133-mobile-map-focus&p=2171');
      await initCoordinateAuditV2132(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
    })
    .catch(error => console.error('Community GIS/house/mobile workflow modules load failed', error));
}

// Isolated registration review: failures do not block existing care workflows.
if(typeof window!=="undefined") import("./house-registration-review-v2202.mjs?v=2.0.158-original-number&p=2208").then(m=>m.initHouseRegistrationReview2202(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY)).catch(()=>{});

// Independent NCD field capture; overview and existing follow-up work remain usable.
if(typeof window!=="undefined") import("./ncd-field-followup-v2203.mjs?v=2.0.155&p=2203").then(m=>m.initNcdFieldFollowup2203(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY)).catch(()=>{});
