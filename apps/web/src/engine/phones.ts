/** Published customer-service numbers → domain. From `vendor/crest/src/lib/phones.ts`. */

const PHONE_DOMAINS: Record<string, string> = {
  "8002211212": "delta.com",
  "8003232323": "delta.com",
  "8004337300": "aa.com",
  "8008648331": "united.com",
  "8004359792": "southwest.com",
  "8002752273": "apple.com",
  "8004633339": "fedex.com",
  "8007425877": "ups.com",
  "8002758777": "usps.com",
  "8009254733": "walgreens.com",
  "8007467287": "cvs.com",
  "8004663337": "homedepot.com",
  "8009359935": "chase.com",
  "8004321000": "bankofamerica.com",
  "8008693557": "wellsfargo.com",
  "8009220204": "verizon.com",
  "8003310500": "att.com",
  "8009378997": "t-mobile.com",
  "8008618380": "geico.com",
  "8005318722": "usaa.com",
  "8007827282": "starbucks.com",
};

const TOLL_FREE = new Set(["800", "888", "877", "866", "855", "844", "833"]);

export function digitsPhone(phone?: string): string | undefined {
  if (!phone) return undefined;
  const d = phone.replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("1")) return d.slice(1);
  if (d.length === 10) return d;
  if (d.length > 10 && d.startsWith("1")) return d.slice(1, 11);
  if (d.length >= 7) return d;
  return undefined;
}

export function isBusinessPhone(phone?: string): boolean {
  const d = digitsPhone(phone);
  if (!d || d.length < 10) return false;
  return TOLL_FREE.has(d.slice(0, 3));
}

export function lookupPhoneDomain(phone?: string): string | undefined {
  const d = digitsPhone(phone);
  if (!d) return undefined;
  return PHONE_DOMAINS[d] ?? (d.length > 10 ? PHONE_DOMAINS[d.slice(-10)] : undefined);
}
