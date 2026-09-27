
import { AIConfig, AIProvider, AIAnalysisResult, QuadrantType, Language } from "../types";

const AI_REQUEST_TIMEOUT_MS = 30000;
const ANTHROPIC_VERSION = '2023-06-01';
const ANTHROPIC_MAX_TOKENS = 8192;

function createRequestSignal(): { signal: AbortSignal; done: () => void } {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), AI_REQUEST_TIMEOUT_MS);
  return { signal: controller.signal, done: () => clearTimeout(timer) };
}

function normalizeRequestError(error: unknown): Error {
  if (error instanceof Error && error.name === 'AbortError') {
    return new Error('Request timed out (30s)');
  }
  return error instanceof Error ? error : new Error(String(error));
}

// --- Protocol helpers (URL conventions follow the provider ecosystems;
// see Cherry Studio / NextChat adapters for the same shapes) ---

function normalizeBaseUrl(baseUrl: string): string {
  let base = (baseUrl || '').trim();
  if (base && !/^https?:\/\//i.test(base)) base = 'https://' + base;
  return base.replace(/\/+$/, '');
}

function joinUrl(baseUrl: string, path: string): string {
  return normalizeBaseUrl(baseUrl) + path;
}

function authHeaders(config: AIConfig): Record<string, string> {
  if (config.provider === AIProvider.Anthropic) {
    // x-api-key is the official header; Bearer is added for OpenAI-style proxies
    return {
      'x-api-key': config.customApiKey || '',
      'anthropic-version': ANTHROPIC_VERSION,
      'Authorization': `Bearer ${config.customApiKey || ''}`
    };
  }
  return { 'Authorization': `Bearer ${config.customApiKey || ''}` };
}

function protocolPath(provider: AIProvider): string {
  switch (provider) {
    case AIProvider.OpenAIResponses: return '/responses';
    case AIProvider.Anthropic: return '/v1/messages';
    default: return '/chat/completions';
  }
}

// Extract the assistant text from each protocol's response envelope
function extractResponseText(provider: AIProvider, data: any): string {
  if (provider === AIProvider.OpenAI) {
    return data?.choices?.[0]?.message?.content ?? '';
  }
  if (provider === AIProvider.OpenAIResponses) {
    if (typeof data?.output_text === 'string' && data.output_text) return data.output_text;
    const parts: string[] = [];
    for (const item of data?.output ?? []) {
      if (item?.type === 'message' && Array.isArray(item.content)) {
        for (const c of item.content) {
          if (c?.type === 'output_text' && typeof c.text === 'string') parts.push(c.text);
        }
      }
    }
    return parts.join('');
  }
  if (provider === AIProvider.Anthropic) {
    return (data?.content ?? [])
      .filter((c: any) => c?.type === 'text' && typeof c.text === 'string')
      .map((c: any) => c.text)
      .join('');
  }
  return '';
}

// POST one chat-style request against the configured protocol and return the text
async function requestCompletion(
  config: AIConfig,
  systemInstruction: string,
  userPrompt: string,
  opts: { forceJsonObject: boolean }
): Promise<string> {
  const defaultBase = config.provider === AIProvider.Anthropic
    ? 'https://api.anthropic.com'
    : 'https://api.deepseek.com';
  const base = normalizeBaseUrl(config.customBaseUrl || defaultBase);
  if (!base || !config.customApiKey) {
    throw new Error('Missing AI endpoint configuration');
  }
  const url = joinUrl(base, protocolPath(config.provider));
  const { signal, done } = createRequestSignal();

  const enableThinking = Boolean(config.enableThinking);
  let body: Record<string, unknown>;
  if (config.provider === AIProvider.OpenAI) {
    body = {
      model: config.customModel || 'deepseek-v4-flash',
      messages: [
        { role: 'system', content: systemInstruction },
        { role: 'user', content: userPrompt }
      ],
      thinking: { type: enableThinking ? 'enabled' : 'disabled' }
    };
    if (opts.forceJsonObject) body.response_format = { type: 'json_object' };
  } else if (config.provider === AIProvider.OpenAIResponses) {
    body = {
      model: config.customModel || 'deepseek-v4-flash',
      instructions: systemInstruction,
      input: userPrompt,
      reasoning: { effort: enableThinking ? 'high' : 'none' }
    };
    if (opts.forceJsonObject) body.text = { format: { type: 'json_object' } };
  } else {
    body = {
      model: config.customModel || 'claude-3-5-haiku-latest',
      max_tokens: ANTHROPIC_MAX_TOKENS,
      system: systemInstruction,
      messages: [{ role: 'user', content: userPrompt }],
      ...(enableThinking
        ? { output_config: { effort: 'high' } }
        : { thinking: { type: 'disabled' } })
    };
  }

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeaders(config) },
      body: JSON.stringify(body),
      signal
    });
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      throw new Error(`API Error ${response.status}: ${detail.slice(0, 200) || response.statusText}`);
    }
    const data = await response.json();
    return extractResponseText(config.provider, data);
  } catch (error) {
    throw normalizeRequestError(error);
  } finally {
    done();
  }
}

// Robust JSON array extraction: direct parse, fence stripping, regex fallback
function asTaskArray(parsed: unknown): unknown[] {
  if (Array.isArray(parsed)) return parsed;
  if (parsed && typeof parsed === 'object') {
    const obj = parsed as Record<string, unknown>;
    if (Array.isArray(obj.tasks)) return obj.tasks;
    if (Array.isArray(obj.data)) return obj.data;
    return [obj];
  }
  return [];
}

function extractJsonArray(text: string): unknown[] {
  if (!text) return [];
  const cleaned = text.replace(/```[a-zA-Z]*\s*/g, '').trim();
  try { return asTaskArray(JSON.parse(cleaned)); } catch { /* keep trying */ }
  const arrMatch = cleaned.match(/\[[\s\S]*\]/);
  if (arrMatch) { try { return asTaskArray(JSON.parse(arrMatch[0])); } catch { /* keep trying */ } }
  const objMatch = cleaned.match(/\{[\s\S]*\}/);
  if (objMatch) { try { return asTaskArray(JSON.parse(objMatch[0])); } catch { /* give up */ } }
  return [];
}

// --- Prompts ---

const getLanguagePromptSuffix = (lang: Language) => {
  switch (lang) {
    case 'zh': return "Please answer in Simplified Chinese.";
    case 'ja': return "Please answer in Japanese.";
    default: return "Please answer in English.";
  }
};

const getSortInstruction = (lang: Language, autoDecompose: boolean) => `
You are an expert productivity assistant based on the Eisenhower Matrix.
Analyze the user's tasks and categorize them into four quadrants:
1. Urgent & Important (Do First)
2. Not Urgent & Important (Schedule)
3. Urgent & Not Important (Delegate)
4. Not Urgent & Not Important (Don't Do/Delete)

STRICT RULES:
1. Identify if a task is "Long Term" (requires breakdown). Set isLongTerm=true.
2. ${autoDecompose
    ? 'IMMEDIATE DECOMPOSITION REQUIRED: If a task is "Long Term" (isLongTerm=true), you MUST break it down NOW into 3-5 actionable, short-term steps and populate the "subtasks" array. DO NOT leave subtasks empty for long term tasks.'
    : 'DO NOT decompose a single task into steps in this phase. If the input is "Running", just return "Running" with isLongTerm=true and subtasks=[].'}
3. GROUPING LOGIC: Always look for multiple DISTINCT input lines that belong to the same project or category (e.g. inputs "Buy milk", "Buy eggs", "Buy soap"). Merge them into one task titled "Shopping" (or appropriate category) with subtasks ["Buy milk", "Buy eggs", "Buy soap"].
4. If an input is a standalone short-term task, leave subtasks empty.
5. The "quadrant" field MUST be the integer 1, 2, 3, or 4 — never a string like "Q1".
6. DO NOT include opinions, advice, preaching, moralizing, or reasons to delete tasks. Keep titles factual and clean.

Important: Respond with ONLY the JSON array, no markdown fences, no extra commentary.
The "title" and "subtasks" fields MUST be in the user's language: ${lang === 'zh' ? 'Simplified Chinese' : lang === 'ja' ? 'Japanese' : 'English'}.
`;

const getBatchDecomposeInstruction = (lang: Language) => `
You are an expert project manager.
You will receive a list of long-term tasks.
For EACH task, break it down into 3-5 immediate, actionable, short-term steps (subtasks) that can be done in under 2 hours each.

Respond with ONLY a JSON array of objects, no markdown fences, no extra commentary.
Format:
[
  { "originalTitle": "Task Name", "subtasks": ["Step 1", "Step 2", "Step 3"] }
]

The strings MUST be in the user's language: ${lang === 'zh' ? 'Simplified Chinese' : lang === 'ja' ? 'Japanese' : 'English'}.
`;

// --- Result normalization ---

function validateQuadrant(q: any): QuadrantType {
  const num = parseInt(String(q).match(/[1-4]/)?.[0] ?? '', 10);
  if (num >= 1 && num <= 4) return num as QuadrantType;
  return QuadrantType.Eliminate;
}

function normalizeAnalysis(rawItems: unknown[]): AIAnalysisResult[] {
  return rawItems.map((item: any) => ({
    title: item?.title ?? '',
    quadrant: validateQuadrant(item?.quadrant),
    isLongTerm: !!item?.isLongTerm,
    reasoning: item?.reasoning,
    subtasks: item?.subtasks || []
  })).filter(r => r.title);
}

// --- Public API ---

export const analyzeTasks = async (
  inputs: string[],
  config: AIConfig,
  lang: Language,
  autoGroup: boolean = false,
  autoDecompose: boolean = false
): Promise<AIAnalysisResult[]> => {
  const langSuffix = getLanguagePromptSuffix(lang);
  const prompt = `Here are the tasks to analyze: ${JSON.stringify(inputs)}. \n\nImportant: ${langSuffix}`;
  const instruction = getSortInstruction(lang, autoDecompose);

  const forceJsonObject = config.provider !== AIProvider.Anthropic;
  const text = await requestCompletion(config, instruction, prompt, { forceJsonObject });
  return normalizeAnalysis(extractJsonArray(text));
};

export const decomposeTasksBatch = async (
  taskTitles: string[],
  config: AIConfig,
  lang: Language
): Promise<{ originalTitle: string, subtasks: string[] }[]> => {
  const langSuffix = getLanguagePromptSuffix(lang);
  const prompt = `Break down these tasks: ${JSON.stringify(taskTitles)}. \n\nImportant: ${langSuffix}`;
  const instruction = getBatchDecomposeInstruction(lang);

  const forceJsonObject = config.provider !== AIProvider.Anthropic;
  const text = await requestCompletion(config, instruction, prompt, { forceJsonObject });
  const items = extractJsonArray(text);
  return items
    .filter((item: any) => item && typeof item.originalTitle === 'string')
    .map((item: any) => ({ originalTitle: item.originalTitle, subtasks: item.subtasks || [] }));
};

// Connection test: probe each protocol with its cheapest listing endpoint,
// falling back to a minimal completion for servers without a models list.
export const testAIConnection = async (
  config: AIConfig,
  t: { error: string; testOk: string; testFail: string }
): Promise<{ ok: boolean; message: string }> => {
  const defaultBase = config.provider === AIProvider.Anthropic
    ? 'https://api.anthropic.com'
    : 'https://api.deepseek.com';
  const base = normalizeBaseUrl(config.customBaseUrl || defaultBase);
  if (!base || !config.customApiKey) {
    return { ok: false, message: `${t.testFail}: URL / KEY` };
  }

  const { signal, done } = createRequestSignal();
  try {
    if (config.provider === AIProvider.Anthropic) {
      let res = await fetch(joinUrl(base, '/v1/models'), { headers: authHeaders(config), signal });
      if (!res.ok && (res.status === 404 || res.status === 405)) {
        // Proxy without a models list: prove liveness with a 1-token completion
        res = await fetch(joinUrl(base, '/v1/messages'), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', ...authHeaders(config) },
          body: JSON.stringify({
            model: config.customModel || 'claude-3-5-haiku-latest',
            max_tokens: 1,
            messages: [{ role: 'user', content: 'hi' }]
          }),
          signal
        });
      }
      return res.ok
        ? { ok: true, message: `${t.testOk} (Anthropic)` }
        : { ok: false, message: `${t.testFail}: ${res.status} ${res.statusText}` };
    }

    const res = await fetch(joinUrl(base, '/models'), { headers: authHeaders(config), signal });
    return res.ok
      ? { ok: true, message: `${t.testOk} (${config.provider})` }
      : { ok: false, message: `${t.testFail}: ${res.status} ${res.statusText}` };
  } catch (error) {
    return { ok: false, message: `${t.testFail}: ${normalizeRequestError(error).message}` };
  } finally {
    done();
  }
};
