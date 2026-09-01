import { describe, it, expect } from 'vitest';
import { cellLink } from './datasetCells';

// The values below are the real ones from FastQC result dataset 114790, measured on
// the production database — a dataset whose job had finished and whose report still
// could not be opened, because every cell was plain text.
const REPORT = 'p35611/FastqcApp_ventricles_100k_2026-09-01_113260_2026-09-01--14-50-05/multi_FastQC/multiqc_report.html';
const FOLDER = 'p35611/FastqcApp_ventricles_100k_2026-09-01_113260_2026-09-01--14-50-05/multi_FastQC';

describe('cellLink', () => {
  it('sends a [Link] value to the gStore server that serves file content', () => {
    expect(cellLink('MultiQC Report [Link]', REPORT)).toEqual({
      href: `https://fgcz-gstore.uzh.ch/projects/${REPORT}`,
      external: true,
    });
  });

  it('uses an absolute [Link] value as it stands, like legacy', () => {
    expect(cellLink('IGV [Link]', 'https://elsewhere.example/report.html')).toEqual({
      href: 'https://elsewhere.example/report.html',
      external: true,
    });
  });

  // These are directories in practice, and we have a browser for directories.
  it('sends a [File] value into our own gStore browser', () => {
    expect(cellLink('MultiQC [File]', FOLDER)).toEqual({
      href: `/files/${FOLDER}`,
      external: false,
    });
  });

  // Legacy's String#tag? matches the tag as a substring of the bracket contents.
  it('treats a multi-tag column as a Link, the order legacy tests in', () => {
    expect(cellLink('IGV [Link,File]', FOLDER)?.external).toBe(true);
  });

  it('leaves untagged columns alone', () => {
    expect(cellLink('Name', 'FastQC')).toBeNull();
    expect(cellLink('Genotype [Factor]', 'wild type')).toBeNull();
  });

  it('leaves an empty or placeholder cell alone', () => {
    expect(cellLink('MultiQC [File]', '')).toBeNull();
    expect(cellLink('MultiQC [File]', '   ')).toBeNull();
    expect(cellLink('MultiQC [File]', '-')).toBeNull();
    expect(cellLink('MultiQC [File]', null)).toBeNull();
    expect(cellLink('MultiQC [File]', undefined)).toBeNull();
  });

  // Legacy joins several paths into one href that cannot resolve. A link certain to
  // 404 is worse than text.
  it('does not link a cell holding several comma-separated paths', () => {
    expect(cellLink('Read1 [File]', 'p1/a.fastq.gz,p1/b.fastq.gz')).toBeNull();
  });

  it('does not double the slash when a value is already rooted', () => {
    expect(cellLink('R [Link]', `/${REPORT}`)?.href).toBe(
      `https://fgcz-gstore.uzh.ch/projects/${REPORT}`,
    );
    expect(cellLink('D [File]', `/${FOLDER}`)?.href).toBe(`/files/${FOLDER}`);
  });
});
