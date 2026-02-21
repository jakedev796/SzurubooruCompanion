/**
 * Reject feed/home and bare-domain URLs that must not be sent as job URLs.
 * Kept in sync with backend app.api.job_url_validation.is_rejected_job_url.
 */

const TWITTER_X_HOSTS = ['x.com', 'www.x.com', 'twitter.com', 'www.twitter.com'];

const REDDIT_HOST_SUFFIXES = ['reddit.com', 'www.reddit.com', 'old.reddit.com', 'new.reddit.com'];

const BARE_DOMAIN_HOST_SUFFIXES = [
  'gelbooru.com',
  'danbooru.donmai.us',
  'safebooru.org',
  'rule34.xxx',
  'yande.re',
  'sankakucomplex.com',
  'sankaku.app',
  'rule34vault.com',
  'misskey.io',
  'misskey.art',
  'misskey.net',
  'misskey.design',
  'misskey.xyz',
  'mi.0px.io',
  'misskey.pizza',
  'x.com',
  'twitter.com',
  'reddit.com',
];

export function isRejectedJobUrl(url: string | null | undefined): boolean {
  if (!url || !url.trim()) return true;
  try {
    const u = new URL(url.trim());
    const scheme = u.protocol.replace(':', '').toLowerCase();
    const host = u.hostname.toLowerCase();
    const path = u.pathname.replace(/\/+$/, '') || '/';
    const pathLower = path.toLowerCase();

    if (scheme !== 'http' && scheme !== 'https') return true;
    if (!host) return true;

    if (TWITTER_X_HOSTS.includes(host) && (pathLower === '/home' || pathLower.startsWith('/home?'))) {
      return true;
    }

    const isReddit = REDDIT_HOST_SUFFIXES.some((s) => host === s || host.endsWith('.' + s));
    if (isReddit) {
      if (path === '/' || path === '') return true;
      if (/^\/r\/[^/]+\/?$/i.test(path)) return true;
      if (!pathLower.includes('/comments/')) return true;
    }

    const isBarePath = path === '/' || path === '';
    if (!isBarePath) return false;
    for (const suffix of BARE_DOMAIN_HOST_SUFFIXES) {
      if (host === suffix || host.endsWith('.' + suffix)) return true;
    }
    return false;
  } catch {
    return true;
  }
}
