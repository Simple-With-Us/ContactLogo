/** Deterministic CompaniesLogo slug picker (Crest).  The live HTML fetch is
 *  native-only (CORS); this module is shared so web tests match Swift. */

const DOMAIN_SLUGS: Record<string, string> = {
  "delta.com": "delta-air-lines",
  "united.com": "united-airlines",
  "aa.com": "american-airlines",
  "southwest.com": "southwest-airlines",
  "homedepot.com": "home-depot",
  "chase.com": "jp-morgan-chase",
  "jpmorganchase.com": "jp-morgan-chase",
  "bankofamerica.com": "bank-of-america",
  "americanexpress.com": "american-express",
  "centerpointenergy.com": "centerpoint-energy",
  "att.com": "att",
  "t-mobile.com": "t-mobile",
  "gm.com": "general-motors",
  "ge.com": "general-electric",
  "pg.com": "procter-and-gamble",
  "jnj.com": "johnson-and-johnson",
  "abc.xyz": "alphabet-google",
  "google.com": "alphabet-google",
  "meta.com": "facebook",
  "facebook.com": "facebook",
};

export function companiesLogoTokens(value: string): string[] {
  return value
    .toLowerCase()
    .replace(/&/g, "and")
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 1 && t !== "the" && t !== "and");
}

export function pickCompaniesLogoSlug(
  catalog: string[],
  opts: { domain?: string; name?: string },
): string | undefined {
  const domain = (opts.domain ?? "").toLowerCase();
  if (domain && DOMAIN_SLUGS[domain] && catalog.includes(DOMAIN_SLUGS[domain])) {
    return DOMAIN_SLUGS[domain];
  }
  const label = domain.split(".")[0] ?? "";
  const nameKey = opts.name ? companiesLogoTokens(opts.name).join("-") : "";
  if (nameKey && catalog.includes(nameKey)) return nameKey;
  if (label && catalog.includes(label)) return label;
  if (label) {
    const prefixed = catalog.filter((s) => s === label || s.startsWith(`${label}-`));
    if (prefixed.length === 1) return prefixed[0];
  }
  const q = companiesLogoTokens(opts.name || label);
  if (!q.length) return undefined;
  let best: { slug: string; score: number } | undefined;
  for (const slug of catalog) {
    const st = slug.split("-");
    const hit = q.filter((t) => st.includes(t)).length;
    if (hit === 0) continue;
    let score = hit * 22;
    if (hit === q.length) score += 28;
    if (st[0] === q[0]) score += 12;
    if (q.length === 1 && st[0] === q[0]) score += 16;
    if (slug === nameKey || slug === label) score += 40;
    score -= Math.max(0, st.length - q.length) * 5;
    if (!best || score > best.score) best = { slug, score };
  }
  return best && best.score >= 50 ? best.slug : undefined;
}

export function pickCompaniesLogoIconHref(html: string): string | undefined {
  const hrefs = [...html.matchAll(/\/img\/orig\/[A-Za-z0-9._-]+\.(?:svg|png)/g)]
    .map((m) => m[0])
    .filter((h) => !h.includes("/icons/") && !h.includes("account.svg") && !h.includes("calendar"));
  const rank = (h: string) => {
    let s = 0;
    const lower = h.toLowerCase();
    if (lower.includes("_big")) s -= 40;
    if (lower.includes(".d-")) s -= 20;
    if (lower.endsWith(".svg")) s += 30;
    if (lower.endsWith(".png")) s += 8;
    return s;
  };
  hrefs.sort((a, b) => rank(b) - rank(a));
  return hrefs[0] ? `https://companieslogo.com${hrefs[0]}` : undefined;
}
