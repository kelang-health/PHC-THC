export const SUPABASE_URL = 'https://tgeezbwbrovfyjbeykrj.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_bw0sKPthqc6Sl9xU8fdVpA_p2sZ4-N2';

if (typeof window !== 'undefined') {
  import('./community-gis.mjs?v=1.8.17')
    .then(({ initCommunityGIS }) => initCommunityGIS(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY))
    .catch(error => console.error('Community GIS load failed', error));
}
