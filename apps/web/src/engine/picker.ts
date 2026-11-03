import type { BookContact } from "./classify.ts";
import { readAsDataUrl } from "./logos.ts";

type ContactInfo = {
  name?: string[];
  email?: string[];
  tel?: string[];
  icon?: Blob[];
};

type ContactsManager = {
  select: (properties: string[], options?: { multiple?: boolean }) => Promise<ContactInfo[]>;
  getProperties?: () => Promise<string[]>;
};

export function canPickDeviceContacts(): boolean {
  if (typeof navigator === "undefined") return false;
  return Boolean((navigator as Navigator & { contacts?: ContactsManager }).contacts);
}

export async function pickDeviceContacts(): Promise<BookContact[]> {
  const api = (navigator as Navigator & { contacts?: ContactsManager }).contacts;
  if (!api) {
    throw new Error("This browser cannot read the phone address book.  Use Chrome for Android, or import a vCard.");
  }
  const wanted = ["name", "email", "tel", "icon"];
  let properties = wanted;
  try {
    const available = await api.getProperties?.();
    if (available?.length) properties = wanted.filter((p) => available.includes(p));
  } catch {
    /* use defaults */
  }
  const picked = await api.select(properties, { multiple: true });
  const contacts: BookContact[] = [];
  for (const row of picked) {
    const name = row.name?.[0]?.trim();
    if (!name) continue;
    let photoDataUrl: string | undefined;
    const icon = row.icon?.[0];
    if (icon) {
      try {
        photoDataUrl = await readAsDataUrl(icon);
      } catch {
        photoDataUrl = undefined;
      }
    }
    contacts.push({
      id: crypto.randomUUID(),
      displayName: name,
      email: row.email?.[0],
      phone: row.tel?.[0],
      photoDataUrl,
      hadExistingPhoto: Boolean(photoDataUrl),
      importSource: "device",
    });
  }
  return contacts;
}
