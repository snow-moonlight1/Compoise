
import { GoogleGenAI, Type } from "@google/genai";
import { AIConfig, AIProvider, AIAnalysisResult, QuadrantType, Language } from "../types";

// Initialize default Gemini client
const geminiClient = new GoogleGenAI({ apiKey: process.env.API_KEY });

const getLanguagePromptSuffix = (lang: Language) => {
  switch (lang) {
    case 'zh': return "Please answer in Simplified Chinese.";
    case 'ja': return "Please answer in Japanese.";
    default: return "Please answer in English.";
  }
};

// Updated: Always instruct to group. The UI determines whether to accept or ask.
const getSortInstruction = (lang: Language) => `
You are an expert productivity assistant based on the Eisenhower Matrix.
Analyze the user's tasks and categorize them into four quadrants:
1. Urgent & Important (Do First)
2. Not Urgent & Important (Schedule)
3. Urgent & Not Important (Delegate)
4. Not Urgent & Not Important (Don't Do/Delete)

STRICT RULES:
1. Identify if a task is "Long Term" (requires breakdown). Set isLongTerm=true.
2. DO NOT decompose a single task into steps in this phase. For example, if the input is "Running", just return "Running" with isLongTerm=true.
3. GROUPING LOGIC: Always look for multiple DISTINCT input lines that belong to the same project or category (e.g. inputs "Buy milk", "Buy eggs", "Buy soap"). Merge them into one task titled "Shopping" (or appropriate category) with subtasks ["Buy milk", "Buy eggs", "Buy soap"].
4. If an input is a standalone task, leave subtasks empty.

Important: Return the output strictly in JSON format.
The "title", "reasoning", and "subtasks" fields MUST be in the user's language: ${lang === 'zh' ? 'Simplified Chinese' : lang === 'ja' ? 'Japanese' : 'English'}.
`;

const getBatchDecomposeInstruction = (lang: Language) => `
You are an expert project manager. 
You will receive a list of long-term tasks. 
For EACH task, break it down into 3-5 immediate, actionable, short-term steps (subtasks) that can be done in under 2 hours each.

Return strictly a JSON Array of Objects.
Format: 
[
  { "originalTitle": "Task Name", "subtasks": ["Step 1", "Step 2", "Step 3"] }
]

The strings MUST be in the user's language: ${lang === 'zh' ? 'Simplified Chinese' : lang === 'ja' ? 'Japanese' : 'English'}.
`;

export const analyzeTasks = async (
  inputs: string[], 
  config: AIConfig,
  lang: Language,
  autoGroup: boolean = false // Kept for signature compatibility, but logic is now handled in App.tsx
): Promise<AIAnalysisResult[]> => {
  const langSuffix = getLanguagePromptSuffix(lang);
  const prompt = `Here are the tasks to analyze: ${JSON.stringify(inputs)}. \n\nImportant: ${langSuffix}`;
  const instruction = getSortInstruction(lang);

  if (config.provider === AIProvider.Gemini) {
    return analyzeWithGemini(prompt, instruction);
  } else {
    return analyzeWithCustom(prompt, config, instruction);
  }
};

export const decomposeTasksBatch = async (
  taskTitles: string[],
  config: AIConfig,
  lang: Language
): Promise<{ originalTitle: string, subtasks: string[] }[]> => {
  const langSuffix = getLanguagePromptSuffix(lang);
  const prompt = `Break down these tasks: ${JSON.stringify(taskTitles)}. \n\nImportant: ${langSuffix}`;
  const instruction = getBatchDecomposeInstruction(lang);

  if (config.provider === AIProvider.Gemini) {
    return decomposeBatchWithGemini(prompt, instruction);
  } else {
    return decomposeBatchWithCustom(prompt, config, instruction);
  }
};

// --- Gemini Implementation ---

async function analyzeWithGemini(prompt: string, systemInstruction: string): Promise<AIAnalysisResult[]> {
  try {
    const response = await geminiClient.models.generateContent({
      model: "gemini-2.5-flash",
      contents: prompt,
      config: {
        systemInstruction: systemInstruction,
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              title: { type: Type.STRING },
              quadrant: { type: Type.INTEGER, description: "1, 2, 3, or 4" },
              isLongTerm: { type: Type.BOOLEAN },
              reasoning: { type: Type.STRING },
              subtasks: { 
                type: Type.ARRAY, 
                items: { type: Type.STRING },
                description: "List of subtasks if grouped, otherwise empty"
              }
            },
            required: ["title", "quadrant", "isLongTerm"]
          }
        }
      }
    });

    const text = response.text;
    if (!text) return [];
    
    const rawData = JSON.parse(text);
    return rawData.map((item: any) => ({
      title: item.title,
      quadrant: validateQuadrant(item.quadrant),
      isLongTerm: !!item.isLongTerm,
      reasoning: item.reasoning,
      subtasks: item.subtasks || []
    }));

  } catch (error) {
    console.error("Gemini Analysis Error:", error);
    throw new Error("Failed to analyze tasks with Gemini.");
  }
}

async function decomposeBatchWithGemini(prompt: string, systemInstruction: string): Promise<{ originalTitle: string, subtasks: string[] }[]> {
  try {
    const response = await geminiClient.models.generateContent({
      model: "gemini-2.5-flash",
      contents: prompt,
      config: {
        systemInstruction: systemInstruction,
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.ARRAY,
          items: {
             type: Type.OBJECT,
             properties: {
                originalTitle: { type: Type.STRING },
                subtasks: { type: Type.ARRAY, items: { type: Type.STRING } }
             }
          }
        }
      }
    });

    const text = response.text;
    if (!text) return [];
    return JSON.parse(text);

  } catch (error) {
    console.error("Gemini Batch Decomposition Error:", error);
    throw new Error("Failed to decompose tasks with Gemini.");
  }
}

// --- Custom (OpenAI Compatible) Implementation ---

async function analyzeWithCustom(prompt: string, config: AIConfig, systemInstruction: string): Promise<AIAnalysisResult[]> {
  if (!config.customBaseUrl || !config.customApiKey) {
    throw new Error("Missing Custom API Configuration");
  }

  const enhancedPrompt = `
    ${systemInstruction}
    
    Response Format Example:
    [
      { 
        "title": "Grocery Shopping", 
        "quadrant": 3, 
        "isLongTerm": false, 
        "reasoning": "routine",
        "subtasks": ["Buy milk", "Buy eggs"] 
      }
    ]

    ${prompt}
  `;

  try {
    const response = await fetch(`${config.customBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.customApiKey}`
      },
      body: JSON.stringify({
        model: config.customModel || 'gpt-3.5-turbo',
        messages: [
          { role: "system", content: systemInstruction },
          { role: "user", content: enhancedPrompt }
        ],
        response_format: { type: "json_object" } 
      })
    });

    if (!response.ok) throw new Error(`Custom API Error: ${response.statusText}`);
    
    const data = await response.json();
    const content = data.choices[0].message.content;
    
    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch {
      const match = content.match(/\[.*\]/s);
      if (match) {
        parsed = JSON.parse(match[0]);
      } else {
        throw new Error("Could not parse JSON from custom model response");
      }
    }

    const results = Array.isArray(parsed) ? parsed : (parsed.tasks || parsed.data || []);
    
    return results.map((item: any) => ({
      title: item.title,
      quadrant: validateQuadrant(item.quadrant),
      isLongTerm: !!item.isLongTerm,
      reasoning: item.reasoning,
      subtasks: item.subtasks || []
    }));

  } catch (error) {
    console.error("Custom API Analysis Error:", error);
    throw error;
  }
}

async function decomposeBatchWithCustom(prompt: string, config: AIConfig, systemInstruction: string): Promise<{ originalTitle: string, subtasks: string[] }[]> {
   if (!config.customBaseUrl || !config.customApiKey) {
    throw new Error("Missing Custom API Configuration");
  }

  const enhancedPrompt = `
    ${systemInstruction}
    Output ONLY a JSON array of objects: [{ "originalTitle": "...", "subtasks": ["..."] }]
    ${prompt}
  `;

  try {
    const response = await fetch(`${config.customBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.customApiKey}`
      },
      body: JSON.stringify({
        model: config.customModel || 'gpt-3.5-turbo',
        messages: [
          { role: "system", content: systemInstruction },
          { role: "user", content: enhancedPrompt }
        ]
      })
    });

    if (!response.ok) throw new Error(`Custom API Error: ${response.statusText}`);
    
    const data = await response.json();
    const content = data.choices[0].message.content;
    
    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch {
       const match = content.match(/\[.*\]/s);
       parsed = match ? JSON.parse(match[0]) : [];
    }
    
    return Array.isArray(parsed) ? parsed : [];

  } catch (error) {
    console.error("Custom API Decomposition Error:", error);
    throw error;
  }
}

// Deprecated singular export for compatibility (wraps batch)
export const decomposeTask = async (
  taskTitle: string,
  config: AIConfig,
  lang: Language
): Promise<string[]> => {
  const results = await decomposeTasksBatch([taskTitle], config, lang);
  return results[0]?.subtasks || [];
};


function validateQuadrant(q: any): QuadrantType {
  const num = parseInt(q);
  if (num >= 1 && num <= 4) return num as QuadrantType;
  return QuadrantType.Eliminate; 
}
