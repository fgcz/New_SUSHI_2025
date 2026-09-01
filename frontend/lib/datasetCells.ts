// Where a dataset cell points, for the columns that name a file.
//
// Legacy SUSHI's data_set/show.html.erb does this per cell:
//
//   [Link] tagged  -> a link. Absolute if the value starts with http, otherwise
//                     to /projects/<value>, which its own web server maps onto
//                     gStore.
//   [File] tagged  -> PLAIN TEXT, no link.
//   missing file   -> red text, no link.
//
// We differ in two places, deliberately:
//
//  * [File] values are directories in practice (measured on the FastQC result
//    dataset 114790: "MultiQC [File]" => "p35611/.../multi_FastQC"). We have a
//    gStore browser of our own, so those become links INTO it. Legacy leaves them
//    dead, so this only adds.
//  * [Link] goes to the external gStore server rather than a path on our own host,
//    because our /api/v1/files lists directories and does not serve file CONTENT —
//    and an HTML report is the whole point. That server answers 401 until the
//    browser supplies the user's own credentials, exactly as legacy's absolute
//    gStore links and its documented `wget --user <login> --ask-password` do.
//
// NOT ported: legacy checks every cell's file for existence and shows missing ones
// in red without a link. Doing that here means stat-ing every file path of every
// sample row on each dataset view — hundreds of calls on a shared filesystem for a
// large dataset. Until that is measured and decided, we link optimistically and a
// file that has not been copied yet answers 404 from gStore.

const GSTORE_BASE = (
  process.env.NEXT_PUBLIC_GSTORE_URL || 'https://fgcz-gstore.uzh.ch/projects'
).replace(/\/+$/, '');

export interface CellLink {
  href: string;
  /** External targets open in a new tab and carry no app session. */
  external: boolean;
}

// Legacy's String#tag? (sushi_fabric/sushiApp.rb): collect the bracket CONTENTS
// and match the tag as a SUBSTRING of them, so "IGV [Link,File]" carries both.
function bracketContents(column: string): string {
  return column.match(/\[(.*)\]/)?.[1] ?? '';
}

function trimSlashes(value: string): string {
  return value.replace(/^\/+/, '');
}

export function cellLink(column: string, value: unknown): CellLink | null {
  const raw = value === null || value === undefined ? '' : String(value).trim();
  if (!raw || raw === '-') return null;

  // A cell may hold several comma-separated paths. Legacy builds ONE link out of
  // the whole joined string, which cannot resolve; a link that is certain to 404
  // is worse than plain text, so leave it as text.
  if (raw.includes(',')) return null;

  const tags = bracketContents(column);

  // Link wins over File when a column carries both, matching the order legacy's
  // view tests them in.
  if (tags.includes('Link')) {
    if (/^https?:\/\//i.test(raw)) return { href: raw, external: true };
    return { href: `${GSTORE_BASE}/${trimSlashes(raw)}`, external: true };
  }

  if (tags.includes('File')) {
    return { href: `/files/${trimSlashes(raw)}`, external: false };
  }

  return null;
}
