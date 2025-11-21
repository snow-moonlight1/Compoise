
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

const getSortInstruction = (lang: Language) => `
You are an expert productivity assistant based on the Eisenhower Matrix.
Analyze the user's tasks and categorize them into four quadrants:
1. Urgent & Important (Do First)
2. Not Urgent & Important (Schedule)
3. Urgent & Not Important (Delegate)
4. Not Urgent & Not Important (Don't Do/Delete)

Also, strictly identify if a task is "Long Term" (requires breakdown, takes > 1 day, or is vague like "Learn Japanese").

Important: Return the output strictly in JSON format.
The "title" and "reasoning" fields MUST be in the user's language: ${lang === 'zh' ? 'Simplified Chinese' : lang === 'ja' ? 'Japanese' : 'English'}.
`;

const getDecomposeInstruction = (lang: Language) => `
You are an expert project manager. The user has a long-term complex task. 
Break it down into 3-5 immediate, actionable, short-term steps (subtasks) that can be done in under 2 hours each.
Return strictly a JSON array of strings.
The strings MUST be in the user's language: ${lang === 'zh' ? 'Simplified Chinese' : lang === 'ja' ? 'Japanese' : 'English'}.
`;

export const analyzeTasks = async (
  inputs: string[], 
  config: AIConfig,
  lang: Language
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

export const decomposeTask = async (
  taskTitle: string,
  config: AIConfig,
  lang: Language
): Promise<string[]> => {
  const langSuffix = getLanguagePromptSuffix(lang);
  const prompt = `Break down this task: "${taskTitle}". \n\nImportant: ${langSuffix}`;
  const instruction = getDecomposeInstruction(lang);

  if (config.provider === AIProvider.Gemini) {
    return decomposeWithGemini(prompt, instruction);
  } else {
    return decomposeWithCustom(prompt, config, instruction);
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
              reasoning: { type: Type.STRING }
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
      reasoning: item.reasoning
    }));

  } catch (error) {
    console.error("Gemini Analysis Error:", error);
    throw new Error("Failed to analyze tasks with Gemini.");
  }
}

async function decomposeWithGemini(prompt: string, systemInstruction: string): Promise<string[]> {
  try {
    const response = await geminiClient.models.generateContent({
      model: "gemini-2.5-flash",
      contents: prompt,
      config: {
        systemInstruction: systemInstruction,
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.ARRAY,
          items: { type: Type.STRING }
        }
      }
    });

    const text = response.text;
    if (!text) return [];
    return JSON.parse(text);

  } catch (error) {
    console.error("Gemini Decomposition Error:", error);
    throw new Error("Failed to decompose task with Gemini.");
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
      { "title": "Buy milk", "quadrant": 3, "isLongTerm": false, "reasoning": "routine" }
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
      reasoning: item.reasoning
    }));

  } catch (error) {
    console.error("Custom API Analysis Error:", error);
    throw error;
  }
}

async function decomposeWithCustom(prompt: string, config: AIConfig, systemInstruction: string): Promise<string[]> {
   if (!config.customBaseUrl || !config.customApiKey) {
    throw new Error("Missing Custom API Configuration");
  }

  const enhancedPrompt = `
    ${systemInstruction}
    Output ONLY a JSON array of strings.
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

function validateQuadrant(q: any): QuadrantType {
  const num = parseInt(q);
  if (num >= 1 && num <= 4) return num as QuadrantType;
  return QuadrantType.Eliminate; 
}
