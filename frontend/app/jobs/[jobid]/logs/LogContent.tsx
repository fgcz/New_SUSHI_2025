'use client';

import { useState } from 'react';

type LineKind = 'trace' | 'info' | 'warn' | 'error' | 'plain';

export type LogIssue = { line: string; kind: 'warn' | 'error'; source: 'out' | 'err' };

export function classifyLine(line: string): LineKind {
  if (line.startsWith('+') || /^Shell debugging/.test(line)) return 'trace';
  if (/INFO[\s(]/.test(line)) return 'info';
  if (/WARN[\s(]/.test(line) || /^Warning[: ]/.test(line) || /^Warning in /.test(line)) return 'warn';
  if (/\berror\b/i.test(line) && !line.startsWith('+')) return 'error';
  return 'plain';
}

export function extractIssues(content: string, source: 'out' | 'err'): LogIssue[] {
  return content.split('\n').flatMap(line => {
    const kind = classifyLine(line);
    if (kind === 'warn' || kind === 'error') return [{ line, kind, source }];
    return [];
  });
}

const lineColors: Record<LineKind, string> = {
  trace: 'text-white',
  info:  'text-white',
  warn:  'text-amber-400',
  error: 'text-red-400',
  plain: 'text-white',
};

type Segment = { type: 'bash-trace'; lines: string[]; collapsible: boolean } | { type: 'content'; lines: string[] };

function isBashTrace(line: string): boolean {
  return line.startsWith('+') || /^Shell debugging/.test(line);
}

function segmentContent(content: string): Segment[] {
  const lines = content.split('\n');
  const segments: Segment[] = [];
  let i = 0;
  let firstBashTraceSeen = false;

  while (i < lines.length) {
    if (isBashTrace(lines[i])) {
      const block: string[] = [];
      while (i < lines.length) {
        const l = lines[i];
        if (isBashTrace(l)) { block.push(l); i++; }
        else if (!l.trim() && i + 1 < lines.length && isBashTrace(lines[i + 1])) { block.push(l); i++; }
        else break;
      }
      if (block.length > 0) {
        const collapsible = !firstBashTraceSeen;
        firstBashTraceSeen = true;
        segments.push({ type: 'bash-trace', lines: block, collapsible });
      }
    } else {
      const block: string[] = [];
      while (i < lines.length && !isBashTrace(lines[i])) {
        block.push(lines[i]);
        i++;
      }
      if (block.length > 0) segments.push({ type: 'content', lines: block });
    }
  }

  return segments;
}

function BashTraceBlock({ lines }: { lines: string[] }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="my-1">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-2 text-xs text-gray-500 hover:text-gray-300 transition-colors py-0.5 w-full text-left select-none"
      >
        <span className="font-mono w-3 shrink-0">{open ? '▼' : '▶'}</span>
        <span>Bash trace</span>
        <span className="text-gray-700">({lines.length} lines)</span>
      </button>
      {open && (
        <div className="border-l border-gray-700 pl-4 mt-0.5">
          {lines.map((line, i) => (
            <div key={i} className="text-white leading-5 whitespace-pre-wrap break-all text-xs">
              {line || ' '}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function LogContent({ content, empty }: { content: string; empty: string }) {
  if (!content) return <p className="text-gray-500 p-4 text-sm font-mono">{empty}</p>;

  const segments = segmentContent(content);

  return (
    <div className="p-4 font-mono text-sm overflow-x-auto">
      {segments.map((seg, i) => {
        if (seg.type === 'bash-trace') {
          if (seg.collapsible) return <BashTraceBlock key={i} lines={seg.lines} />;
          return (
            <div key={i}>
              {seg.lines.map((line, j) => (
                <div key={j} className="leading-5 whitespace-pre-wrap break-all text-white">
                  {line || ' '}
                </div>
              ))}
            </div>
          );
        }
        return (
          <div key={i}>
            {seg.lines.map((line, j) => (
              <div key={j} className={`leading-5 whitespace-pre-wrap break-all ${lineColors[classifyLine(line)]}`}>
                {line || ' '}
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
}
