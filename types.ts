
export enum QuadrantType {
  Do = 1,       // Urgent & Important
  Plan = 2,     // Not Urgent & Important
  Delegate = 3, // Urgent & Not Important
  Eliminate = 4 // Not Urgent & Not Important
}

export interface Board {
  id: string;
  name: string;
  createdAt: number;
}

export interface SubTask {
  id: string;
  title: string;
  completed: boolean;
  deadline?: number; // Added deadline
}

export interface Task {
  id: string;
  boardId: string;
  title: string;
  quadrant: QuadrantType;
  isLongTerm: boolean;
  completed: boolean;
  createdAt: number;
  deadline?: number; // Timestamp
  subtasks?: SubTask[];
}

export interface AIAnalysisResult {
  title: string;
  quadrant: QuadrantType;
  isLongTerm: boolean;
  reasoning?: string;
  subtasks?: string[]; // AI returns strings, converted to SubTasks later
}

export enum AIProvider {
  Gemini = 'gemini',
  Custom = 'custom'
}

export type Language = 'en' | 'zh' | 'ja';
export type ThemeMode = 'system' | 'light' | 'dark';
export type ThemeColor = 'blue' | 'purple' | 'green' | 'orange' | 'pink';
export type InputMode = 'single' | 'brainDump';

export interface AppSettings {
  language: Language;
  theme: ThemeMode;
  themeColor: ThemeColor;
  defaultInputMode: InputMode;
  autoGroupAI: boolean; 
  autoDecomposeAI: boolean; // New: Auto decompose long-term
  suppressGroupPrompt: boolean; // New: Don't show group prompt (default to split)
  suppressLongTermPrompt: boolean; // New: Don't show long-term prompt (default to keep)
  urgencyThresholdDays: number; 
}

export interface AIConfig {
  provider: AIProvider;
  customBaseUrl?: string;
  customApiKey?: string;
  customModel?: string;
}

export interface ExportData {
    version: number;
    timestamp: number;
    boards: Board[];
    tasks: Task[];
    settings: AppSettings;
    aiConfig: AIConfig;
}

// SVG Icon Props
export interface IconProps {
  className?: string;
  size?: number;
}
