import { getSharedSession, sharedCall } from './shared-runtime-v2035.mjs?v=2.0.126-log-usage';

// Display geometry changes infrequently. Save/check RPCs must always stay live.
export const MAP_REFERENCE_TTL_MS = 10 * 60 * 1000;
export async function readMapReference(client, resource, loader) {
  try {
    const session = await getSharedSession(client);
    if (!session?.user?.id) return { data: null, error: new Error('AUTH_REQUIRED') };
    return await sharedCall(`map-reference-v2188:${session.user.id}:${resource}`, async () => {
      const result = await loader();
      if (result?.error) throw result.error;
      return result;
    }, MAP_REFERENCE_TTL_MS);
  } catch (error) {
    // A failed read must be retried, rather than cached as an empty boundary.
    return { data: null, error };
  }
}
