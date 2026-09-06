
import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Task, QuadrantType, AIConfig, AIProvider, AppSettings, InputMode, Board, ThemeColor, SubTask, ExportData } from './types';
import { analyzeTasks, decomposeTasksBatch, testAIConnection } from './services/aiService';
import { translations } from './translations';
import {
  SparklesIcon, SettingsIcon, PlusIcon,
  AlertTriangleIcon, LoaderIcon, SplitIcon, TrashIcon,
  MoonIcon, SunIcon, GlobeIcon, MonitorIcon, LayersIcon, DownloadIcon, UploadIcon, CalendarIcon, PencilIcon,
  EyeIcon, EyeOffIcon
} from './components/Icons';

// UI Components
import { Modal } from './components/ui/Modal';
import { Checkbox } from './components/ui/Checkbox';
import { ToastStack, ToastItem, ToastType } from './components/ui/Toast';

// Feature Components
import { Quadrant } from './components/Quadrant';
import { InputArea } from './components/InputArea';
import { SettingsControls } from './components/SettingsControls';
import { ImportReview } from './components/ImportReview';

// --- Helpers ---

// localStorage JSON read that never crashes the app on corrupted data
function safeParse<T>(key: string, fallback: T, onCorrupt?: () => void): T {
  const raw = localStorage.getItem(key);
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    onCorrupt?.();
    return fallback;
  }
}

// Parse a YYYY-MM-DD date input as LOCAL midnight (not UTC) so deadlines
// behave intuitively in any timezone.
function parseDateInput(dateStr: string): number | undefined {
  if (!dateStr) return undefined;
  const [y, m, d] = dateStr.split('-').map(Number);
  if (!y || !m || !d) return undefined;
  return new Date(y, m - 1, d).getTime();
}

// Serialize a timestamp as a YYYY-MM-DD string in local time (toISOString is UTC).
function formatDateLocal(timestamp?: number): string {
  if (!timestamp) return '';
  const date = new Date(timestamp);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

// --- Main App ---

export default function App() {
  // --- State ---
  const [boards, setBoards] = useState<Board[]>([]);
  const [activeBoardId, setActiveBoardId] = useState<string>('');
  const [tasks, setTasks] = useState<Task[]>([]);
  
  // UI State
  const [inputMode, setInputMode] = useState<InputMode>('single');
  const [inputText, setInputText] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [addModalOpen, setAddModalOpen] = useState(false);
  
  // Board Menu State with Animation
  const [boardMenuOpen, setBoardMenuOpen] = useState(false);
  const [boardMenuClosing, setBoardMenuClosing] = useState(false);

  const [renameBoardId, setRenameBoardId] = useState<string | null>(null);
  const [newBoardName, setNewBoardName] = useState('');
  
  // Confirmation Modal State (Split for animation stability)
  const [confirmData, setConfirmData] = useState<{
      type: 'deleteTask' | 'deleteBoard' | 'clearQuadrant' | 'overwriteImport';
      id: string;
      title?: string;
  } | null>(null);
  const [isConfirmOpen, setIsConfirmOpen] = useState(false);

  // Import Flow State
  const [importStage, setImportStage] = useState<'none' | 'mode-select' | 'settings-review'>('none');
  const [pendingImport, setPendingImport] = useState<ExportData | null>(null);
  const [tempSettings, setTempSettings] = useState<AppSettings | null>(null);
  const [importSelection, setImportSelection] = useState<Set<string>>(new Set());
  
  // New Workflow State: Group Suggestion Queue & Batch Long-Term Queue
  const [pendingTasks, setPendingTasks] = useState<Task[]>([]);
  const [groupingQueue, setGroupingQueue] = useState<Task[]>([]);
  const [longTermBatchQueue, setLongTermBatchQueue] = useState<Task[]>([]);
  const [longTermSelectedIds, setLongTermSelectedIds] = useState<Set<string>>(new Set());
  
  // Single Decompose State
  const [singleDecomposingTask, setSingleDecomposingTask] = useState<Task | null>(null);

  // Grouping State
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [selectedTaskIds, setSelectedTaskIds] = useState<Set<string>>(new Set());
  const [groupModalOpen, setGroupModalOpen] = useState(false);
  const [groupTitleInput, setGroupTitleInput] = useState('');

  // Edit State (Overhauled)
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  // For Single Task Edit
  const [editTitleInput, setEditTitleInput] = useState('');
  const [editDateInput, setEditDateInput] = useState('');
  const [editQuadrant, setEditQuadrant] = useState<QuadrantType>(QuadrantType.Do);
  // For Group Edit
  const [editGroupSelectedIds, setEditGroupSelectedIds] = useState<Set<string>>(new Set());
  const [inlineEditId, setInlineEditId] = useState<string | null>(null); // ID of subtask or 'parent' being edited
  const [inlineEditText, setInlineEditText] = useState('');
  const [showDatePicker, setShowDatePicker] = useState(false);

  // Toasts
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const toastIdRef = useRef(0);

  // Drag feedback
  const [dragOverQuadrant, setDragOverQuadrant] = useState<QuadrantType | null>(null);

  // Connection test
  const [testingConnection, setTestingConnection] = useState(false);


  // Config & Settings State
  const [aiConfig, setAiConfig] = useState<AIConfig>({
    provider: AIProvider.OpenAI,
    customBaseUrl: '',
    customApiKey: '',
    customModel: 'gpt-4o-mini'
  });

  const [appSettings, setAppSettings] = useState<AppSettings>({
    language: 'en',
    theme: 'system',
    themeColor: 'blue',
    defaultInputMode: 'single',
    autoGroupAI: false,
    autoDecomposeAI: false,
    autoCompleteParent: false,
    suppressGroupPrompt: false,
    suppressLongTermPrompt: false,
    hideCompleted: false,
    urgencyThresholdDays: 3
  });

  // Persistence is enabled only after the initial load has run, so an empty
  // state (or a crash mid-load) can never wipe saved data.
  const [hydrated, setHydrated] = useState(false);

  // Helper for translations
  const t = translations[appSettings.language];

  const pushToast = useCallback((message: string, type: ToastType) => {
    const id = ++toastIdRef.current;
    setToasts(prev => [...prev, { id, message, type }]);
  }, []);

  const dismissToast = useCallback((id: number) => {
    setToasts(prev => prev.filter(item => item.id !== id));
  }, []);

  // --- Effects ---

  useEffect(() => {
    let corrupted = 0;
    const onCorrupt = () => { corrupted += 1; };

    const savedConfig = safeParse<typeof aiConfig>('matrixflow-config', null as unknown as typeof aiConfig, onCorrupt);
    if (savedConfig) {
      // Legacy providers map to the OpenAI-compatible protocol
      const legacy = (savedConfig as any).provider;
      if (legacy === 'custom' || legacy === 'gemini') savedConfig.provider = AIProvider.OpenAI;
      setAiConfig({ ...{
          provider: AIProvider.OpenAI,
          customBaseUrl: '',
          customApiKey: '',
          customModel: 'gpt-4o-mini'
        }, ...savedConfig });
    }

    const savedSettings = safeParse<Partial<AppSettings>>('matrixflow-settings', null as unknown as Partial<AppSettings>, onCorrupt);
    if (savedSettings) {
      setAppSettings({
         language: savedSettings.language ?? 'en',
         theme: savedSettings.theme ?? 'system',
         themeColor: savedSettings.themeColor ?? 'blue',
         defaultInputMode: savedSettings.defaultInputMode ?? 'single',
         autoGroupAI: savedSettings.autoGroupAI ?? false,
         autoDecomposeAI: savedSettings.autoDecomposeAI ?? false,
         autoCompleteParent: savedSettings.autoCompleteParent ?? false,
         suppressGroupPrompt: savedSettings.suppressGroupPrompt ?? false,
         suppressLongTermPrompt: savedSettings.suppressLongTermPrompt ?? false,
         hideCompleted: savedSettings.hideCompleted ?? false,
         urgencyThresholdDays: savedSettings.urgencyThresholdDays ?? 3
      });
      setInputMode(savedSettings.defaultInputMode ?? 'single');
    }

    const loadedBoards = safeParse<Board[]>('matrixflow-boards', [], onCorrupt);
    const loadedTasks = safeParse<Task[]>('matrixflow-tasks', [], onCorrupt);

    let tasksOut: Task[] = [];

    if (loadedTasks.length > 0 && !loadedTasks[0].boardId) {
      const defaultBoardId = crypto.randomUUID();
      if (loadedBoards.length === 0) {
        loadedBoards.push({ id: defaultBoardId, name: t.defaultBoardName, createdAt: Date.now() });
      }
      const targetBoardId = loadedBoards[0]?.id || defaultBoardId;
      tasksOut = loadedTasks.map((task: any) => ({ ...task, boardId: targetBoardId }));
    } else {
      tasksOut = loadedTasks;
    }

    if (loadedBoards.length === 0) {
      const newBoard = { id: crypto.randomUUID(), name: t.defaultBoardName, createdAt: Date.now() };
      loadedBoards.push(newBoard);
    }

    setBoards(loadedBoards);
    setTasks(tasksOut);
    setActiveBoardId(loadedBoards[0].id);
    setHydrated(true);

    if (corrupted > 0) pushToast(t.localStorageCorrupt, 'error');

  }, []);

  // Save changes (after hydration; empty lists persist too, so clearing all
  // tasks no longer resurrects them on reload)
  useEffect(() => { if (hydrated) localStorage.setItem('matrixflow-tasks', JSON.stringify(tasks)); }, [tasks, hydrated]);
  useEffect(() => { if (hydrated) localStorage.setItem('matrixflow-boards', JSON.stringify(boards)); }, [boards, hydrated]);
  useEffect(() => { if (hydrated) localStorage.setItem('matrixflow-config', JSON.stringify(aiConfig)); }, [aiConfig, hydrated]);
  useEffect(() => { if (hydrated) localStorage.setItem('matrixflow-settings', JSON.stringify(appSettings)); }, [appSettings, hydrated]);

  // Keep <html lang> in sync with the UI language
  useEffect(() => {
    document.documentElement.lang = appSettings.language;
  }, [appSettings.language]);

  // Auto-Move Tasks based on Deadline
  useEffect(() => {
     if (tasks.length === 0) return;
     
     const checkDeadlines = () => {
       const now = Date.now();
       const thresholdMs = appSettings.urgencyThresholdDays * 24 * 60 * 60 * 1000;
       
       let hasChanges = false;
       const updatedTasks = tasks.map(task => {
         if (!task.deadline || task.completed) return task;

         const timeLeft = task.deadline - now;
         // Move Q2 (Plan) -> Q1 (Do)
         if (task.quadrant === QuadrantType.Plan && timeLeft <= thresholdMs) {
           hasChanges = true;
           return { ...task, quadrant: QuadrantType.Do };
         }
         // Move Q4 (Eliminate) -> Q3 (Delegate)
         if (task.quadrant === QuadrantType.Eliminate && timeLeft <= thresholdMs) {
           hasChanges = true;
           return { ...task, quadrant: QuadrantType.Delegate };
         }
         return task;
       });

       if (hasChanges) {
         setTasks(updatedTasks);
       }
     };

     checkDeadlines();
     const interval = setInterval(checkDeadlines, 1000 * 60 * 60);
     return () => clearInterval(interval);

  }, [tasks, appSettings.urgencyThresholdDays]);

  // Theme & Color Handling
  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    if (appSettings.theme === 'system') {
      if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
        root.classList.add('dark');
      } else {
        root.classList.add('light');
      }
    } else {
      root.classList.add(appSettings.theme);
    }
    const colorMap: Record<ThemeColor, string> = {
      blue: '#3b82f6',
      purple: '#8b5cf6',
      green: '#10b981',
      orange: '#f97316',
      pink: '#ec4899'
    };
    root.style.setProperty('--primary', colorMap[appSettings.themeColor] || '#3b82f6');
  }, [appSettings.theme, appSettings.themeColor]);

  // --- Derived Data ---

  const activeBoard = boards.find(b => b.id === activeBoardId);
  const visibleTasks = useMemo(
    () => tasks.filter(t => t.boardId === activeBoardId && (!appSettings.hideCompleted || !t.completed)),
    [tasks, activeBoardId, appSettings.hideCompleted]
  );
  const doTasks = useMemo(() => visibleTasks.filter(t => t.quadrant === QuadrantType.Do), [visibleTasks]);
  const planTasks = useMemo(() => visibleTasks.filter(t => t.quadrant === QuadrantType.Plan), [visibleTasks]);
  const delegateTasks = useMemo(() => visibleTasks.filter(t => t.quadrant === QuadrantType.Delegate), [visibleTasks]);
  const eliminateTasks = useMemo(() => visibleTasks.filter(t => t.quadrant === QuadrantType.Eliminate), [visibleTasks]);

  // --- AI Connection Test ---

  const handleTestConnection = async () => {
      setTestingConnection(true);
      try {
          const result = await testAIConnection(aiConfig, { error: t.error, testOk: t.testOk, testFail: t.testFail });
          pushToast(result.message, result.ok ? 'success' : 'error');
      } catch (err) {
          console.error(err);
          pushToast(t.testFail, 'error');
      } finally {
          setTestingConnection(false);
      }
  };

  // --- Handlers ---

  const openAddModal = () => {
    setInputMode(appSettings.defaultInputMode);
    setAddModalOpen(true);
  };

  const handleDragStart = useCallback((e: React.DragEvent, task: Task) => {
    e.dataTransfer.setData('taskId', task.id);
    e.dataTransfer.effectAllowed = 'move';
    setDragOverQuadrant(task.quadrant);
  }, []);

  const handleDragEnd = useCallback(() => {
    setDragOverQuadrant(null);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent, quadrant: QuadrantType) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    setDragOverQuadrant(prev => (prev === quadrant ? prev : quadrant));
  }, []);

  const handleDrop = useCallback((e: React.DragEvent, targetQuadrant: QuadrantType) => {
    e.preventDefault();
    setDragOverQuadrant(null);
    const taskId = e.dataTransfer.getData('taskId');
    if (!taskId) return;
    setTasks(prev => prev.map(t =>
      t.id === taskId ? { ...t, quadrant: targetQuadrant } : t
    ));
  }, []);

  // --- Deletion Logic with Confirmation ---

  const handleDeleteTaskTrigger = useCallback((id: string) => {
      setConfirmData({ type: 'deleteTask', id });
      setIsConfirmOpen(true);
  }, []);

  const handleClearQuadrantTrigger = useCallback((type: QuadrantType) => {
      setConfirmData({ type: 'clearQuadrant', id: String(type) });
      setIsConfirmOpen(true);
  }, []);
  
  const handleDeleteBoardTrigger = (id: string) => {
     if (boards.length <= 1) return; 
     setConfirmData({ type: 'deleteBoard', id });
     setIsConfirmOpen(true);
  };

  const executeConfirmAction = () => {
      if (!confirmData) return;
      const { type, id } = confirmData;

      if (type === 'deleteTask') {
          setTasks(prev => prev.filter(t => t.id !== id));
      } else if (type === 'clearQuadrant') {
          const qType = parseInt(id) as QuadrantType;
          setTasks(prev => prev.filter(t => !(t.boardId === activeBoardId && t.quadrant === qType)));
      } else if (type === 'deleteBoard') {
          setBoards(prev => prev.filter(b => b.id !== id));
          setTasks(prev => prev.filter(t => t.boardId !== id));
          if (activeBoardId === id) {
              const remaining = boards.filter(b => b.id !== id);
              if (remaining.length > 0) setActiveBoardId(remaining[0].id);
          }
      } else if (type === 'overwriteImport') {
          runOverwriteImport();
      }
      setIsConfirmOpen(false);
      // Data persists for animation, will be overwritten next open
  };

  // Destructive overwrite, run only from the confirmation modal
  const runOverwriteImport = () => {
      if (!pendingImport) return;
      setBoards(pendingImport.boards);
      setTasks(pendingImport.tasks);
      if (pendingImport.boards.length > 0) setActiveBoardId(pendingImport.boards[0].id);
      if (pendingImport.settings) {
          setTempSettings(pendingImport.settings);
          setImportStage('settings-review');
      } else {
          closeImportFlow();
          pushToast(t.importSuccess, 'success');
      }
  };

  // Helper: Flatten grouped tasks into individuals
  const flattenTasks = (groupedTasks: Task[]) => {
      let flat: Task[] = [];
      groupedTasks.forEach(t => {
          if (t.subtasks && t.subtasks.length > 0) {
             // It's a group, flatten it
             t.subtasks.forEach(sub => {
                 flat.push({
                    id: crypto.randomUUID(),
                    boardId: t.boardId,
                    title: sub.title,
                    quadrant: t.quadrant,
                    isLongTerm: false,
                    completed: false,
                    createdAt: Date.now(),
                    subtasks: []
                 });
             });
          } else {
             flat.push(t);
          }
      });
      return flat;
  };

  // Helper: Execute batch decompose with provided list
  const executeBatchDecompose = useCallback(async (tasksToDecompose: Task[]) => {
      if (tasksToDecompose.length === 0) return;

      const titles = tasksToDecompose.map(t => t.title);
      const ids = new Set(tasksToDecompose.map(t => t.id));

      try {
          const results = await decomposeTasksBatch(titles, aiConfig, appSettings.language);

          setTasks(prev => prev.map(t => {
              if (!ids.has(t.id)) return t;

              const result = results.find(r => r.originalTitle === t.title);
              if (result) {
                  const newSubs: SubTask[] = result.subtasks.map(st => ({
                      id: crypto.randomUUID(),
                      title: st,
                      completed: false
                  }));
                  return { ...t, subtasks: [...(t.subtasks || []), ...newSubs] };
              }
              return t;
          }));
      } catch (err) {
          console.error(err);
          pushToast(err instanceof Error ? `${t.error}: ${err.message}` : t.error, 'error');
      }
  }, [aiConfig, appSettings.language, pushToast]);

  // New consolidated process for adding analyzed tasks
  const processFinalTasks = async (incomingTasks: Task[]) => {
      let tasksToProcess = [...incomingTasks];

      // Scenario: Auto Decompose is ON
      if (appSettings.autoDecomposeAI) {
          // Find tasks that should have been decomposed but AI might have missed subtasks in first pass
          const tasksNeedingDecomposition = tasksToProcess.filter(t => t.isLongTerm && (!t.subtasks || t.subtasks.length === 0));
          
          if (tasksNeedingDecomposition.length > 0) {
              try {
                  // Perform a silent batch decomposition BEFORE adding to state
                  const results = await decomposeTasksBatch(
                      tasksNeedingDecomposition.map(t => t.title), 
                      aiConfig, 
                      appSettings.language
                  );
                  
                  // Update the tasks in memory
                  tasksToProcess = tasksToProcess.map(t => {
                      const res = results.find(r => r.originalTitle === t.title);
                      if (res && t.isLongTerm && (!t.subtasks || t.subtasks.length === 0)) {
                          const newSubs: SubTask[] = res.subtasks.map(st => ({
                              id: crypto.randomUUID(),
                              title: st,
                              completed: false
                          }));
                          return { ...t, subtasks: newSubs };
                      }
                      return t;
                  });
              } catch (e) {
                  console.error("Silent decomposition correction failed", e);
              }
          }
          
          setTasks(prev => [...tasksToProcess, ...prev]);
          setIsProcessing(false);

      } else {
          // Scenario: Auto Decompose is OFF
          setTasks(prev => [...tasksToProcess, ...prev]);
          
          const longTerms = tasksToProcess.filter(t => t.isLongTerm && (!t.subtasks || t.subtasks.length === 0));
          
          if (longTerms.length > 0 && !appSettings.suppressLongTermPrompt) {
              setLongTermBatchQueue(longTerms);
              const initialIds = new Set<string>();
              longTerms.forEach(t => initialIds.add(t.id));
              setLongTermSelectedIds(initialIds);
          }
          setIsProcessing(false);
      }
  };

  const handleAISort = async () => {
    if (!inputText.trim()) return;
    
    setIsProcessing(true);
    try {
      const rawTasks = inputText.split('\n').filter(t => t.trim().length > 0);
      const results = await analyzeTasks(
        rawTasks, 
        aiConfig, 
        appSettings.language, 
        appSettings.autoGroupAI,
        appSettings.autoDecomposeAI
      );
      
      const newTasks: Task[] = results.map(res => ({
        id: crypto.randomUUID(),
        boardId: activeBoardId,
        title: res.title,
        quadrant: res.quadrant,
        isLongTerm: res.isLongTerm,
        completed: false,
        createdAt: Date.now(),
        reasoning: res.reasoning,
        subtasks: res.subtasks?.map(st => ({
          id: crypto.randomUUID(),
          title: st,
          completed: false
        })) || []
      }));
      
      setInputText('');
      if (addModalOpen) setAddModalOpen(false);

      // --- Workflow Phase 2: Grouping ---
      let tasksForPhase3 = [];

      if (appSettings.autoGroupAI) {
         // Auto-accept all structures
         tasksForPhase3 = newTasks;
      } else if (appSettings.suppressGroupPrompt) {
         // Auto-reject groups (flatten)
         tasksForPhase3 = flattenTasks(newTasks);
      } else {
         // Check for groups to prompt
         const potentialGroups = newTasks.filter(t => t.subtasks && t.subtasks.length > 0);
         if (potentialGroups.length > 0) {
            setPendingTasks(newTasks.filter(t => !t.subtasks || t.subtasks.length === 0));
            setGroupingQueue(potentialGroups);
            // Stop here, wait for modal interactions
            return;
         } else {
            tasksForPhase3 = newTasks;
         }
      }
      
      // Proceed if no modal needed
      processFinalTasks(tasksForPhase3);
      
    } catch (err) {
      console.error(err);
      pushToast(err instanceof Error ? `${t.error}: ${err.message}` : t.error, 'error');
      setIsProcessing(false);
    }
  };

  // Workflow: Handle Group Suggestion Decision
  const handleGroupDecision = (accepted: boolean) => {
      const currentGroup = groupingQueue[0];
      const remainingQueue = groupingQueue.slice(1);
      
      let finalTasks: Task[] = [];
      
      if (accepted) {
          finalTasks = [currentGroup];
      } else {
          // Split
          finalTasks = flattenTasks([currentGroup]);
      }
      
      // Update pending tasks
      const updatedPending = [...pendingTasks, ...finalTasks];
      setPendingTasks(updatedPending);
      setGroupingQueue(remainingQueue);

      if (remainingQueue.length === 0) {
          // Groups resolved, move to Phase 3
          processFinalTasks(updatedPending);
      }
  };

  // Workflow: Handle Batch Decomposition (From Modal)
  const handleBatchDecompose = async () => {
      if (longTermSelectedIds.size === 0) {
          handleSkipBatchDecompose();
          return;
      }

      setIsProcessing(true); 
      const tasksToDecompose = longTermBatchQueue.filter(t => longTermSelectedIds.has(t.id));
      
      await executeBatchDecompose(tasksToDecompose);
      
      setLongTermBatchQueue([]);
      setIsProcessing(false);
      setLongTermSelectedIds(new Set());
  };

  const handleSkipBatchDecompose = () => {
    setLongTermBatchQueue([]);
    setIsProcessing(false);
    setLongTermSelectedIds(new Set());
  };

  // Individual Decompose (Manual trigger)
  const handleManualDecompose = useCallback(async (task: Task) => {
      setSingleDecomposingTask(task);
      try {
         await executeBatchDecompose([task]);
      } catch (err) {
         console.error(err);
         pushToast(t.error, 'error');
      } finally {
         setSingleDecomposingTask(null);
      }
  }, [executeBatchDecompose, pushToast]);

  const handleManualAdd = () => {
    if (!inputText.trim()) return;

    // Split multi-line input into separate tasks, consistent with AI mode
    const lines = inputText.split('\n').map(line => line.trim()).filter(Boolean);
    const newTasks: Task[] = lines.map(line => ({
      id: crypto.randomUUID(),
      boardId: activeBoardId,
      title: line,
      quadrant: QuadrantType.Do,
      isLongTerm: false,
      completed: false,
      createdAt: Date.now(),
    }));
    setTasks(prev => [...newTasks, ...prev]);
    setInputText('');
    if (addModalOpen) setAddModalOpen(false);
  };

  // General Update Handler
  const handleTaskUpdate = useCallback((updatedTask: Task) => {
    if (appSettings.autoCompleteParent && updatedTask.subtasks && updatedTask.subtasks.length > 0) {
        const total = updatedTask.subtasks.length;
        const completed = updatedTask.subtasks.filter(s => s.completed).length;

        if (total > 0 && total === completed) {
             updatedTask.completed = true;
        } else if (updatedTask.completed && total !== completed) {
             updatedTask.completed = false;
        }
    }
    setTasks(prev => prev.map(t => t.id === updatedTask.id ? updatedTask : t));
  }, [appSettings.autoCompleteParent]);

  // Cascading Parent Checkbox Logic
  const handleParentCheck = useCallback((task: Task) => {
    const newStatus = !task.completed;
    const updatedSubtasks = task.subtasks?.map(s => ({
      ...s,
      completed: newStatus
    }));

    const newTask = {
      ...task,
      completed: newStatus,
      subtasks: updatedSubtasks
    };
    setTasks(prev => prev.map(t => t.id === newTask.id ? newTask : t));
  }, []);

  // Selection & Grouping Handlers
  const toggleSelectionMode = () => {
    setIsSelectionMode(!isSelectionMode);
    setSelectedTaskIds(new Set());
  };

  const handleToggleSelect = useCallback((id: string) => {
    const newSet = new Set(selectedTaskIds);
    if (newSet.has(id)) newSet.delete(id);
    else newSet.add(id);
    setSelectedTaskIds(newSet);
  }, [selectedTaskIds]);

  const openGroupModal = () => {
      if (selectedTaskIds.size < 2) return;
      setGroupTitleInput('');
      setGroupModalOpen(true);
  };

  const handleConfirmGroup = () => {
    if (!groupTitleInput.trim()) {
        setGroupModalOpen(false);
        return;
    }
    const selectedTasks = tasks.filter(t => selectedTaskIds.has(t.id));
    if (selectedTasks.length === 0) return;

    const firstTask = selectedTasks[0];
    const newSubtasks: SubTask[] = selectedTasks.map(t => ({
      id: crypto.randomUUID(),
      title: t.title,
      completed: t.completed,
      deadline: t.deadline
    }));

    const parentTask: Task = {
      id: crypto.randomUUID(),
      boardId: firstTask.boardId,
      title: groupTitleInput,
      quadrant: firstTask.quadrant,
      isLongTerm: false,
      completed: false,
      createdAt: Date.now(),
      subtasks: newSubtasks,
      deadline: undefined
    };

    setTasks(prev => {
      const remaining = prev.filter(t => !selectedTaskIds.has(t.id));
      return [parentTask, ...remaining];
    });

    setGroupModalOpen(false);
    setIsSelectionMode(false);
    setSelectedTaskIds(new Set());
  };

  // --- Edit Logic Handlers ---

  const openEditModal = useCallback((task: Task) => {
      setEditingTask(task);
      setEditGroupSelectedIds(new Set());
      setInlineEditId(null);
      setShowDatePicker(false);
      setEditQuadrant(task.quadrant);

      // Single task init
      setEditTitleInput(task.title);
      setEditDateInput(formatDateLocal(task.deadline));
  }, []);

  const handleEditGroupSelect = (id: string) => {
      const newSet = new Set(editGroupSelectedIds);
      if (newSet.has(id)) newSet.delete(id);
      else newSet.add(id);
      setEditGroupSelectedIds(newSet);
  };

  const startInlineEdit = (id: string, initialText: string) => {
      setInlineEditId(id);
      setInlineEditText(initialText);
  };

  const saveInlineEdit = () => {
      if (!editingTask || !inlineEditId) return;
      const text = inlineEditText.trim();
      
      let updatedTask = { ...editingTask };

      if (inlineEditId === 'parent') {
          if (text) updatedTask.title = text;
      } else {
          const subs = updatedTask.subtasks?.map(s => s.id === inlineEditId ? { ...s, title: text || s.title } : s);
          updatedTask.subtasks = subs;
      }
      
      setEditingTask(updatedTask);
      handleTaskUpdate(updatedTask);
      setInlineEditId(null);
  };

  const applyGroupDeadline = (dateStr: string) => {
      if (!editingTask || !dateStr) return;
      const timestamp = parseDateInput(dateStr);
      if (timestamp === undefined) return;
      
      let updatedTask = { ...editingTask };
      
      if (editGroupSelectedIds.has('parent')) {
          updatedTask.deadline = timestamp;
      }
      
      if (updatedTask.subtasks) {
          const subs = updatedTask.subtasks.map(s => editGroupSelectedIds.has(s.id) ? { ...s, deadline: timestamp } : s);
          updatedTask.subtasks = subs;
      }

      setEditingTask(updatedTask);
      handleTaskUpdate(updatedTask);
      setShowDatePicker(false);
      setEditGroupSelectedIds(new Set());
  };

  const saveSingleEdit = () => {
      if (!editingTask) return;
      const timestamp = parseDateInput(editDateInput);
      const newTitle = editTitleInput.trim();

      if (!newTitle) return;

      handleTaskUpdate({ ...editingTask, title: newTitle, deadline: timestamp, quadrant: editQuadrant });
      setEditingTask(null);
  };

  // Board Management Handlers
  const toggleBoardMenu = () => {
    if (boardMenuOpen) {
      setBoardMenuClosing(true);
      setTimeout(() => {
        setBoardMenuClosing(false);
        setBoardMenuOpen(false);
      }, 200); // Fast match animation
    } else {
      setBoardMenuOpen(true);
    }
  };

  const handleCreateBoard = () => {
    const newBoard: Board = {
      id: crypto.randomUUID(),
      name: t.untitledBoard,
      createdAt: Date.now()
    };
    setBoards(prev => [...prev, newBoard]);
    setActiveBoardId(newBoard.id);
    setRenameBoardId(newBoard.id);
    setNewBoardName(t.untitledBoard);
    toggleBoardMenu();
  };

  const handleDeleteBoard = (id: string) => {
      handleDeleteBoardTrigger(id);
  };

  const handleRenameBoard = () => {
    if (!newBoardName.trim() || !renameBoardId) return;
    setBoards(prev => prev.map(b => b.id === renameBoardId ? { ...b, name: newBoardName } : b));
    setRenameBoardId(null);
    setNewBoardName('');
  };

  // Import / Export Handlers
  const handleExport = () => {
      const data: ExportData = {
          version: 1,
          timestamp: Date.now(),
          boards,
          tasks,
          settings: appSettings,
          aiConfig
      };
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `matrixflow_backup_${new Date().toISOString().split('T')[0]}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = (event) => {
          try {
              const content = event.target?.result as string;
              if (!content) return;
              const json = JSON.parse(content);

              if (!Array.isArray(json.boards) || !Array.isArray(json.tasks)) {
                  pushToast(t.importError, 'error');
                  return;
              }

              setPendingImport(json);
              setImportSelection(new Set([
                'language', 'theme', 'themeColor', 'inputMode', 'aiProvider', 'hideCompleted',
                'autoDecomposeAI', 'suppressLongTermPrompt', 'autoGroupAI', 'suppressGroupPrompt', 'autoCompleteParent', 'urgencyThresholdDays'
              ]));

              setImportStage('mode-select');

          } catch (err) {
              console.error(err);
              pushToast(t.importError, 'error');
          } finally {
              e.target.value = '';
          }
      };
      reader.readAsText(file);
  };

  const executeImportTasks = (mode: 'merge' | 'overwrite') => {
      if (!pendingImport) return;

      if (mode === 'overwrite') {
          // Destructive: close mode selection and require explicit confirmation
          setImportStage('none');
          setConfirmData({ type: 'overwriteImport', id: 'overwriteImport' });
          setIsConfirmOpen(true);
          return;
      }

      const existingBoardIds = new Set(boards.map(b => b.id));
      const newBoards = pendingImport.boards.filter(b => !existingBoardIds.has(b.id));

      setBoards(prev => [...prev, ...newBoards]);

      // Deduplicate by id and drop tasks whose board no longer exists
      const seenTaskIds = new Set(tasks.map(t => t.id));
      const validBoardIds = new Set([...existingBoardIds, ...newBoards.map(b => b.id)]);
      const incoming = pendingImport.tasks.filter(t => !seenTaskIds.has(t.id) && validBoardIds.has(t.boardId));
      setTasks(prev => [...prev, ...incoming]);

      if (pendingImport.settings) {
          setTempSettings(pendingImport.settings);
          setImportStage('settings-review');
      } else {
          closeImportFlow();
          pushToast(t.importSuccess, 'success');
      }
  };

  const applyImportSettings = () => {
      if (tempSettings) {
          setAppSettings(prev => {
              const next = { ...prev };
              if (importSelection.has('language')) next.language = tempSettings.language;
              if (importSelection.has('theme')) next.theme = tempSettings.theme;
              if (importSelection.has('themeColor')) next.themeColor = tempSettings.themeColor;
              if (importSelection.has('inputMode')) next.defaultInputMode = tempSettings.defaultInputMode;
              
              if (importSelection.has('autoDecomposeAI')) next.autoDecomposeAI = tempSettings.autoDecomposeAI;
              if (importSelection.has('suppressLongTermPrompt')) next.suppressLongTermPrompt = tempSettings.suppressLongTermPrompt;
              if (importSelection.has('autoGroupAI')) next.autoGroupAI = tempSettings.autoGroupAI;
              if (importSelection.has('suppressGroupPrompt')) next.suppressGroupPrompt = tempSettings.suppressGroupPrompt;
              if (importSelection.has('autoCompleteParent')) next.autoCompleteParent = tempSettings.autoCompleteParent;
              if (importSelection.has('urgencyThresholdDays')) next.urgencyThresholdDays = tempSettings.urgencyThresholdDays;
      if (importSelection.has('hideCompleted')) next.hideCompleted = tempSettings.hideCompleted;

              return next;
          });
      }
      if (pendingImport?.aiConfig && importSelection.has('aiProvider')) {
          setAiConfig(pendingImport.aiConfig);
      }
      closeImportFlow();
      pushToast(t.importSuccess, 'success');
  };

  const closeImportFlow = () => {
      setImportStage('none');
      setPendingImport(null);
      setTempSettings(null);
      setSettingsOpen(false);
      setImportSelection(new Set());
  };


  return (
    <div className="h-screen flex flex-col overflow-hidden selection:bg-primary selection:text-white font-sans">
      
      {/* --- Header --- */}
      <header className="flex-none h-16 flex items-center justify-between px-6 z-20 relative">
        <div className="flex items-center gap-3">
          {/* Board Switcher */}
          <div className="relative">
             <button 
               onClick={toggleBoardMenu}
               className="flex items-center gap-2 font-bold text-lg text-slate-700 dark:text-slate-200 hover:text-primary transition-colors"
             >
               {activeBoard?.name || t.defaultBoardName}
               <svg 
                  className={`w-4 h-4 transition-transform duration-200 ${boardMenuOpen && !boardMenuClosing ? 'rotate-180' : ''}`} 
                  fill="none" viewBox="0 0 24 24" stroke="currentColor"
               >
                 <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
               </svg>
             </button>

             {(boardMenuOpen || boardMenuClosing) && (
               <div className={`absolute top-full left-0 mt-2 w-64 neu-flat rounded-xl p-2 origin-top z-50 shadow-xl ${boardMenuClosing ? 'animate-slide-back-up' : 'animate-slide-down'}`}>
                 <div className="max-h-60 overflow-y-auto custom-scrollbar">
                   {boards.map(board => (
                     <div key={board.id} className="group flex items-center justify-between p-2 rounded-lg hover:bg-slate-200/50 dark:hover:bg-slate-700/50 transition-colors">
                        {renameBoardId === board.id ? (
                          <input 
                            autoFocus
                            value={newBoardName}
                            onChange={(e) => setNewBoardName(e.target.value)}
                            onBlur={handleRenameBoard}
                            onKeyDown={(e) => e.key === 'Enter' && handleRenameBoard()}
                            className="w-full bg-transparent text-sm font-bold outline-none"
                          />
                        ) : (
                          <button 
                            onClick={() => { setActiveBoardId(board.id); toggleBoardMenu(); }}
                            className={`flex-1 text-left text-sm font-bold truncate ${activeBoardId === board.id ? 'text-primary' : 'text-slate-600 dark:text-slate-300'}`}
                          >
                            {board.name}
                          </button>
                        )}
                        
                        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button onClick={() => { setRenameBoardId(board.id); setNewBoardName(board.name); }} className="p-1 hover:text-primary"><SettingsIcon size={12}/></button>
                          {boards.length > 1 && (
                            <button onClick={() => handleDeleteBoard(board.id)} className="p-1 hover:text-red-500"><TrashIcon size={12}/></button>
                          )}
                        </div>
                     </div>
                   ))}
                 </div>
                 <div className="h-px bg-slate-300 dark:bg-slate-600 my-2"></div>
                 <button onClick={handleCreateBoard} className="w-full text-left p-2 text-sm font-bold text-primary hover:bg-slate-200/50 dark:hover:bg-slate-700/50 rounded-lg flex items-center gap-2 transition-colors">
                    <PlusIcon size={14} /> {t.createBoard}
                 </button>
               </div>
             )}
          </div>
        </div>
        
        <div className="flex items-center gap-2">
            {/* Selection Mode Toggle */}
            <button
              onClick={toggleSelectionMode}
              className={`neu-btn px-3 py-2 rounded-lg transition-colors flex items-center gap-2 ${isSelectionMode ? 'text-primary ring-1 ring-primary' : 'text-slate-500 dark:text-slate-400'}`}
            >
              <LayersIcon size={18} />
              <span className="hidden md:inline text-xs font-bold">{isSelectionMode ? t.cancelSelection : t.selectionMode}</span>
            </button>

            {isSelectionMode && selectedTaskIds.size >= 2 && (
               <button
                 onClick={openGroupModal}
                 className="neu-btn px-3 py-2 rounded-lg text-primary font-bold text-xs animate-pop-in"
               >
                 {t.groupSelected} ({selectedTaskIds.size})
               </button>
            )}

            {/* Hide Completed Toggle */}
            <button
              onClick={() => setAppSettings(s => ({ ...s, hideCompleted: !s.hideCompleted }))}
              className={`neu-btn p-3 rounded-full transition-colors active:scale-95 ${appSettings.hideCompleted ? 'text-primary ring-1 ring-primary' : 'text-slate-500 dark:text-slate-400 hover:text-primary'}`}
              title={t.hideCompleted}
              aria-label={t.hideCompleted}
              aria-pressed={appSettings.hideCompleted}
            >
              {appSettings.hideCompleted ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
            </button>

            <button
              onClick={() => setSettingsOpen(true)}
              aria-label={t.settings}
              title={t.settings}
              className="neu-btn p-3 rounded-full text-slate-500 dark:text-slate-400 hover:text-primary transition-colors active:scale-95"
            >
              <SettingsIcon />
            </button>
        </div>
      </header>

      {/* --- Main Content --- */}
      <div className="flex-1 flex flex-col md:flex-row gap-6 px-4 md:px-8 pb-6 md:pb-8 overflow-hidden">
        
        {/* Desktop Input Panel */}
        <div className="hidden md:block w-80 flex-none flex flex-col gap-4">
           <div className="neu-flat rounded-2xl p-6 flex-1 flex flex-col min-h-0">
              <InputArea 
                  inputMode={inputMode} 
                  setInputMode={setInputMode} 
                  inputText={inputText} 
                  setInputText={setInputText} 
                  handleAISort={handleAISort} 
                  handleManualAdd={handleManualAdd} 
                  isProcessing={isProcessing} 
                  t={t} 
              />
           </div>
        </div>

        {/* The Matrix Grid */}
        <div className="flex-1 grid grid-cols-2 grid-rows-2 gap-3 md:gap-6 h-full">
          <Quadrant
            type={QuadrantType.Do}
            title={t.q1} shortTitle={t.q1Short} colorCode="q1"
            tasks={doTasks}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
            isDragOver={dragOverQuadrant === QuadrantType.Do}
            onDelete={handleDeleteTaskTrigger}
            onClear={handleClearQuadrantTrigger}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            onParentCheck={handleParentCheck}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
          <Quadrant
            type={QuadrantType.Plan}
            title={t.q2} shortTitle={t.q2Short} colorCode="q2"
            tasks={planTasks}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
            isDragOver={dragOverQuadrant === QuadrantType.Plan}
            onDelete={handleDeleteTaskTrigger}
            onClear={handleClearQuadrantTrigger}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            onParentCheck={handleParentCheck}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
          <Quadrant
            type={QuadrantType.Delegate}
            title={t.q3} shortTitle={t.q3Short} colorCode="q3"
            tasks={delegateTasks}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
            isDragOver={dragOverQuadrant === QuadrantType.Delegate}
            onDelete={handleDeleteTaskTrigger}
            onClear={handleClearQuadrantTrigger}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            onParentCheck={handleParentCheck}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
          <Quadrant
            type={QuadrantType.Eliminate}
            title={t.q4} shortTitle={t.q4Short} colorCode="q4"
            tasks={eliminateTasks}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
            isDragOver={dragOverQuadrant === QuadrantType.Eliminate}
            onDelete={handleDeleteTaskTrigger}
            onClear={handleClearQuadrantTrigger}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            onParentCheck={handleParentCheck}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
        </div>

      </div>

      {/* Mobile FAB */}
      <button
        onClick={openAddModal}
        aria-label={t.addBtn}
        className="md:hidden absolute bottom-8 right-6 w-14 h-14 rounded-full bg-primary text-white shadow-lg shadow-primary/40 flex items-center justify-center active:scale-90 transition-transform z-30 animate-pop-in"
      >
        <PlusIcon size={28} />
      </button>

      {/* Toasts */}
      <ToastStack toasts={toasts} onDismiss={dismissToast} />

      {/* --- Modals --- */}

      {/* Confirmation Modal - Using stable data */}
      <Modal
          isOpen={isConfirmOpen}
          onClose={() => setIsConfirmOpen(false)}
          title={
              confirmData?.type === 'deleteTask' ? t.deleteTaskTitle :
              confirmData?.type === 'deleteBoard' ? t.deleteBoardTitle :
              confirmData?.type === 'overwriteImport' ? t.importModeOverwrite :
              t.clearQuadrantTitle
          }
      >
          <div className="space-y-6">
              <div className="neu-concave p-5 rounded-xl flex items-center gap-4 text-red-500">
                  <div className="p-3 bg-red-100 dark:bg-red-900/20 rounded-full flex-none">
                     <AlertTriangleIcon size={28} className="animate-pulse" />
                  </div>
                  <p className="text-sm font-bold text-slate-600 dark:text-slate-300">
                      {confirmData?.type === 'deleteTask' ? t.deleteTaskConfirm :
                       confirmData?.type === 'deleteBoard' ? t.confirmDeleteBoard :
                       confirmData?.type === 'overwriteImport' ? t.confirmImport :
                       t.confirmClearQuadrant}
                  </p>
              </div>

              <div className="flex gap-4">
                  <button
                      onClick={() => {
                          if (confirmData?.type === 'overwriteImport') setImportStage('mode-select');
                          setIsConfirmOpen(false);
                      }}
                      className="neu-btn flex-1 py-3 rounded-xl text-slate-500 font-bold text-sm hover:text-slate-700 dark:hover:text-slate-200 active:scale-95 transition-all"
                  >
                      {t.cancel}
                  </button>
                  <button
                      onClick={executeConfirmAction}
                      className="neu-btn flex-1 py-3 rounded-xl text-red-500 font-bold text-sm hover:text-red-600 active:scale-95 transition-all"
                  >
                      {t.confirm}
                  </button>
              </div>
          </div>
      </Modal>

      {/* Mobile Add Task Modal */}
      <Modal isOpen={addModalOpen} onClose={() => setAddModalOpen(false)} title={t.addBtn}>
         <InputArea 
            inputMode={inputMode} 
            setInputMode={setInputMode} 
            inputText={inputText} 
            setInputText={setInputText} 
            handleAISort={handleAISort} 
            handleManualAdd={handleManualAdd} 
            isProcessing={isProcessing} 
            t={t} 
         />
      </Modal>

      {/* Redesigned Edit Modal */}
      <Modal isOpen={!!editingTask} onClose={() => setEditingTask(null)} title={editingTask?.subtasks?.length ? t.editTask : t.editTask}>
         {editingTask && (
             editingTask.subtasks && editingTask.subtasks.length > 0 ? (
                 // --- Complex Group Edit View ---
                 <div className="flex flex-col h-[60vh]">
                     <div className="flex-1 overflow-y-auto custom-scrollbar p-1 space-y-2">
                        {/* Parent Item */}
                        <div 
                          className={`p-3 rounded-xl transition-all border ${editGroupSelectedIds.has('parent') ? 'bg-primary/5 border-primary' : 'bg-transparent border-transparent hover:bg-slate-100 dark:hover:bg-slate-800'}`}
                          onClick={() => handleEditGroupSelect('parent')}
                          onDoubleClick={() => startInlineEdit('parent', editingTask.title)}
                        >
                            {inlineEditId === 'parent' ? (
                                <input 
                                  autoFocus
                                  value={inlineEditText}
                                  onChange={(e) => setInlineEditText(e.target.value)}
                                  onBlur={saveInlineEdit}
                                  onKeyDown={(e) => e.key === 'Enter' && saveInlineEdit()}
                                  className="w-full bg-white dark:bg-slate-700 rounded px-2 py-1 outline-none text-sm font-bold"
                                />
                            ) : (
                                <div className="flex justify-between items-center">
                                    <span className="font-bold text-slate-700 dark:text-slate-200">{editingTask.title}</span>
                                    {editingTask.deadline && <CalendarIcon size={14} className="text-primary" />}
                                </div>
                            )}
                        </div>

                        {/* Subtasks List */}
                        <div className="pl-4 space-y-1 border-l-2 border-slate-200 dark:border-slate-700 ml-3">
                            {editingTask.subtasks.map(sub => (
                                <div 
                                  key={sub.id}
                                  className={`p-2 rounded-lg transition-all border cursor-pointer ${editGroupSelectedIds.has(sub.id) ? 'bg-primary/5 border-primary' : 'bg-transparent border-transparent hover:bg-slate-100 dark:hover:bg-slate-800'}`}
                                  onClick={() => handleEditGroupSelect(sub.id)}
                                  onDoubleClick={() => startInlineEdit(sub.id, sub.title)}
                                >
                                    {inlineEditId === sub.id ? (
                                        <input 
                                          autoFocus
                                          value={inlineEditText}
                                          onChange={(e) => setInlineEditText(e.target.value)}
                                          onBlur={saveInlineEdit}
                                          onKeyDown={(e) => e.key === 'Enter' && saveInlineEdit()}
                                          className="w-full bg-white dark:bg-slate-700 rounded px-2 py-1 outline-none text-xs"
                                        />
                                    ) : (
                                        <div className="flex justify-between items-center">
                                            <span className="text-sm text-slate-600 dark:text-slate-300">{sub.title}</span>
                                            {sub.deadline && <CalendarIcon size={12} className="text-primary" />}
                                        </div>
                                    )}
                                </div>
                            ))}
                        </div>
                     </div>

                     {/* Bottom Action Bar */}
                     <div className="pt-4 border-t border-slate-200 dark:border-slate-700 mt-2">
                        {showDatePicker ? (
                            <div className="animate-slide-up bg-white dark:bg-slate-800 p-2 rounded-xl shadow-lg border border-slate-100 dark:border-slate-700">
                                <label className="text-xs font-bold text-slate-500 mb-2 block">{t.setDeadline}</label>
                                <input 
                                  type="date" 
                                  className="w-full p-2 rounded bg-slate-100 dark:bg-slate-900 outline-none mb-2"
                                  onChange={(e) => applyGroupDeadline(e.target.value)}
                                />
                                <button onClick={() => setShowDatePicker(false)} className="text-xs text-slate-400 underline w-full text-center">{t.cancel}</button>
                            </div>
                        ) : (
                            <button 
                              disabled={editGroupSelectedIds.size === 0}
                              onClick={() => setShowDatePicker(true)}
                              className="neu-btn w-full py-3 rounded-xl flex items-center justify-center gap-2 text-primary font-bold disabled:opacity-50 disabled:cursor-not-allowed active:scale-95"
                            >
                                <CalendarIcon />
                                {t.setDeadline} {editGroupSelectedIds.size > 0 && `(${editGroupSelectedIds.size})`}
                            </button>
                        )}
                     </div>
                 </div>
             ) : (
                 // --- Simple Task Edit View (Modernized) ---
                 <div className="flex flex-col h-[60vh] md:h-auto">
                     <div className="flex-1 space-y-4 p-1">
                         {/* Title Input Card */}
                         <div className="space-y-2">
                             <label className="text-xs font-bold text-slate-500 ml-1">{t.boardName.replace('Board Name', 'Task Name').replace('任务板名称', '任务名称').replace('ボード名', 'タスク名')}</label>
                             <div className="neu-pressed rounded-xl p-3 flex items-start gap-2 bg-slate-50 dark:bg-slate-800/50">
                                 <PencilIcon className="text-slate-400 mt-1 flex-none" size={16} />
                                 <textarea
                                   rows={3}
                                   value={editTitleInput}
                                   onChange={(e) => setEditTitleInput(e.target.value)}
                                   className="w-full bg-transparent border-none outline-none text-sm font-bold text-slate-700 dark:text-slate-200 resize-none placeholder-slate-400"
                                   placeholder="Task Title"
                                 />
                             </div>
                         </div>
                         
                         {/* Deadline Input Card */}
                         <div className="space-y-2">
                              <label className="text-xs font-bold text-slate-500 ml-1">{t.setDeadline}</label>
                              <div className="neu-flat rounded-xl p-1 flex items-center bg-white dark:bg-slate-700">
                                 <input
                                   type="date"
                                   value={editDateInput}
                                   onChange={(e) => setEditDateInput(e.target.value)}
                                   className="w-full bg-transparent outline-none p-2 text-sm text-slate-600 dark:text-slate-300 font-bold"
                                 />
                              </div>
                         </div>

                         {/* Quadrant Picker Card */}
                         <div className="space-y-2">
                              <label className="text-xs font-bold text-slate-500 ml-1">{t.quadrant}</label>
                              <div className="grid grid-cols-2 gap-2">
                                  {([QuadrantType.Do, QuadrantType.Plan, QuadrantType.Delegate, QuadrantType.Eliminate] as const).map(q => (
                                      <button
                                          key={q}
                                          onClick={() => setEditQuadrant(q)}
                                          aria-pressed={editQuadrant === q}
                                          className={`flex items-center gap-2 px-2 py-2 rounded-lg text-xs font-bold transition-all ${editQuadrant === q ? 'neu-pressed ring-1 ring-primary text-slate-700 dark:text-slate-200' : 'neu-flat text-slate-500'}`}
                                      >
                                          <span className={`w-2 h-2 rounded-full flex-none ${q === QuadrantType.Do ? 'bg-q1' : q === QuadrantType.Plan ? 'bg-q2' : q === QuadrantType.Delegate ? 'bg-q3' : 'bg-q4'}`} />
                                          {q === QuadrantType.Do ? t.q1Short : q === QuadrantType.Plan ? t.q2Short : q === QuadrantType.Delegate ? t.q3Short : t.q4Short}
                                      </button>
                                  ))}
                              </div>
                         </div>
                     </div>

                     {/* Action Button */}
                     <div className="pt-4 mt-auto">
                         <button 
                           onClick={saveSingleEdit}
                           className="neu-btn w-full py-3 rounded-xl text-primary font-bold text-sm hover:opacity-90 active:scale-95 transition-all flex justify-center items-center gap-2"
                         >
                           <SparklesIcon size={18} />
                           {t.addSingleBtn}
                         </button>
                     </div>
                 </div>
             )
         )}
      </Modal>

      {/* Settings Modal */}
      <Modal isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} title={t.settings}>
        <div className="space-y-6">
          
          {/* Language Section */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <GlobeIcon size={16} /> {t.language}
            </label>
            <div className="flex gap-2">
              {(['en', 'zh', 'ja'] as const).map(lang => (
                <button
                  key={lang}
                  onClick={() => setAppSettings(s => ({ ...s, language: lang }))}
                  className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all duration-300 ${appSettings.language === lang ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
                >
                  {lang === 'en' ? 'EN' : lang === 'zh' ? '中文' : '日本語'}
                </button>
              ))}
            </div>
          </div>

          {/* Theme Mode Section */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
              <SunIcon size={16} /> {t.theme}
            </label>
            <div className="flex gap-2">
               <button
                 onClick={() => setAppSettings(s => ({ ...s, theme: 'light' }))}
                 className={`flex-1 py-2 rounded-lg text-xs font-bold flex flex-col items-center gap-1 transition-all duration-300 ${appSettings.theme === 'light' ? 'neu-pressed text-primary scale-105' : 'neu-flat text-slate-500'}`}
               >
                 <SunIcon size={16}/> {t.themeLight}
               </button>
               <button
                 onClick={() => setAppSettings(s => ({ ...s, theme: 'dark' }))}
                 className={`flex-1 py-2 rounded-lg text-xs font-bold flex flex-col items-center gap-1 transition-all duration-300 ${appSettings.theme === 'dark' ? 'neu-pressed text-primary scale-105' : 'neu-flat text-slate-500'}`}
               >
                 <MoonIcon size={16}/> {t.themeDark}
               </button>
               <button
                 onClick={() => setAppSettings(s => ({ ...s, theme: 'system' }))}
                 className={`flex-1 py-2 rounded-lg text-xs font-bold flex flex-col items-center gap-1 transition-all duration-300 ${appSettings.theme === 'system' ? 'neu-pressed text-primary scale-105' : 'neu-flat text-slate-500'}`}
               >
                 <MonitorIcon size={16}/> {t.themeSystem}
               </button>
            </div>
          </div>

          {/* Theme Color Picker */}
          <div>
             <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
                <SparklesIcon size={16} /> {t.themeColor}
             </label>
             <div className="flex justify-between px-2">
                {(['blue', 'purple', 'green', 'orange', 'pink'] as const).map(color => (
                  <button
                    key={color}
                    onClick={() => setAppSettings(s => ({ ...s, themeColor: color }))}
                    aria-label={color === 'blue' ? t.colorBlue : color === 'purple' ? t.colorPurple : color === 'green' ? t.colorGreen : color === 'orange' ? t.colorOrange : t.colorPink}
                    title={color === 'blue' ? t.colorBlue : color === 'purple' ? t.colorPurple : color === 'green' ? t.colorGreen : color === 'orange' ? t.colorOrange : t.colorPink}
                    className={`w-8 h-8 rounded-full flex items-center justify-center transition-all duration-300 ${appSettings.themeColor === color ? 'ring-2 ring-offset-2 ring-slate-400 scale-110' : 'hover:scale-105'}`}
                    style={{ backgroundColor: color === 'blue' ? '#3b82f6' : color === 'purple' ? '#8b5cf6' : color === 'green' ? '#10b981' : color === 'orange' ? '#f97316' : '#ec4899' }}
                  />
                ))}
             </div>
          </div>

          {/* Grouping & Automation (Reused Control) */}
          <div>
             <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <LayersIcon size={16} /> {t.grouping}
             </label>
             <SettingsControls settings={appSettings} setSettings={setAppSettings} t={t} />
          </div>

          <hr className="border-slate-300 dark:border-slate-700" />

          {/* Data Backup */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <DownloadIcon size={16} /> {t.dataManagement}
            </label>
            <div className="flex gap-2">
              <button 
                 onClick={handleExport}
                 className="flex-1 neu-btn py-2 rounded-lg text-sm font-bold text-primary flex items-center justify-center gap-2 active:scale-95"
              >
                 <DownloadIcon size={16}/> {t.exportData}
              </button>
              <label className="flex-1 neu-btn py-2 rounded-lg text-sm font-bold text-slate-600 dark:text-slate-300 flex items-center justify-center gap-2 cursor-pointer active:scale-95">
                 <UploadIcon size={16}/> {t.importData}
                 <input 
                   type="file" 
                   accept=".json" 
                   onChange={handleFileSelect} 
                   className="hidden" 
                   onClick={(e) => (e.target as HTMLInputElement).value = ''}
                 />
              </label>
            </div>
          </div>

          <hr className="border-slate-300 dark:border-slate-700" />

          {/* Default Mode Section */}
          <div>
             <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <SettingsIcon size={16} /> {t.defaultMode}
             </label>
             <div className="flex bg-slate-200 dark:bg-slate-700/30 p-1 rounded-lg">
                <button 
                   onClick={() => setAppSettings(s => ({ ...s, defaultInputMode: 'single' }))}
                   className={`flex-1 py-1.5 text-xs font-bold rounded-md transition-all duration-200 ${appSettings.defaultInputMode === 'single' ? 'bg-white dark:bg-slate-600 shadow-sm text-slate-800 dark:text-white' : 'text-slate-500'}`}
                >
                  {t.modeManual}
                </button>
                <button 
                   onClick={() => setAppSettings(s => ({ ...s, defaultInputMode: 'brainDump' }))}
                   className={`flex-1 py-1.5 text-xs font-bold rounded-md transition-all duration-200 ${appSettings.defaultInputMode === 'brainDump' ? 'bg-white dark:bg-slate-600 shadow-sm text-slate-800 dark:text-white' : 'text-slate-500'}`}
                >
                  {t.modeAI}
                </button>
             </div>
          </div>

          <hr className="border-slate-300 dark:border-slate-700" />

          {/* AI Provider Config */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2">{t.provider}</label>
            <div className="grid grid-cols-2 gap-2 mb-3">
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.OpenAI }))}
                className={`py-2 rounded-lg text-xs font-bold transition-all ${aiConfig.provider === AIProvider.OpenAI ? 'neu-pressed text-green-500' : 'neu-flat text-slate-500'}`}
              >
                {t.providerOpenAI}
              </button>
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.OpenAIResponses }))}
                className={`py-2 rounded-lg text-xs font-bold transition-all ${aiConfig.provider === AIProvider.OpenAIResponses ? 'neu-pressed text-green-500' : 'neu-flat text-slate-500'}`}
              >
                {t.providerOpenAIResponses}
              </button>
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.Anthropic }))}
                className={`col-span-2 py-2 rounded-lg text-xs font-bold transition-all ${aiConfig.provider === AIProvider.Anthropic ? 'neu-pressed text-orange-500' : 'neu-flat text-slate-500'}`}
              >
                {t.providerAnthropic}
              </button>
            </div>

            <div className="space-y-3 p-3 neu-concave rounded-xl animate-fade-in mb-3">
              <div>
                <label htmlFor="customBaseUrlInput" className="text-xs font-bold text-slate-400">{t.customBaseUrl}</label>
                <input
                  id="customBaseUrlInput"
                  type="text"
                  value={aiConfig.customBaseUrl}
                  onChange={(e) => setAiConfig(c => ({ ...c, customBaseUrl: e.target.value }))}
                  className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                />
              </div>
              <div>
                <label htmlFor="customApiKeyInput" className="text-xs font-bold text-slate-400">{t.customApiKey}</label>
                <input
                  id="customApiKeyInput"
                  type="password"
                  value={aiConfig.customApiKey}
                  onChange={(e) => setAiConfig(c => ({ ...c, customApiKey: e.target.value }))}
                  className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                />
              </div>
              <div>
                <label htmlFor="customModelInput" className="text-xs font-bold text-slate-400">{t.customModel}</label>
                <input
                  id="customModelInput"
                  type="text"
                  value={aiConfig.customModel}
                  onChange={(e) => setAiConfig(c => ({ ...c, customModel: e.target.value }))}
                  className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                />
              </div>
              <p className="text-[11px] text-slate-400 leading-snug">{t.customUrlHint}</p>
            </div>

            {/* Connection Test */}
            <button
              onClick={handleTestConnection}
              disabled={testingConnection}
              className="w-full mt-3 neu-btn py-2 rounded-lg text-xs font-bold text-slate-600 dark:text-slate-300 flex items-center justify-center gap-2 active:scale-95 disabled:opacity-50"
            >
              {testingConnection
                ? <LoaderIcon size={14} className="animate-spin" />
                : <SparklesIcon size={14} />}
              {testingConnection ? t.processing : t.testConnection}
            </button>
          </div>
        </div>
      </Modal>

       {/* Import Stage 1: Mode Selection */}
      <Modal isOpen={importStage === 'mode-select'} onClose={closeImportFlow} title={t.importOptions}>
          <div className="space-y-4">
              <p className="text-sm text-slate-500">{t.importPrompt}</p>
              <button 
                  onClick={() => executeImportTasks('merge')}
                  className="w-full p-4 neu-btn rounded-xl flex flex-col items-start gap-1 active:scale-95"
              >
                  <span className="font-bold text-primary">{t.importModeMerge}</span>
                  <span className="text-xs text-slate-500">{t.importModeMergeDesc}</span>
              </button>
              <button 
                  onClick={() => executeImportTasks('overwrite')}
                  className="w-full p-4 neu-btn rounded-xl flex flex-col items-start gap-1 active:scale-95 hover:text-red-500"
              >
                  <span className="font-bold text-slate-700 dark:text-slate-200">{t.importModeOverwrite}</span>
                  <span className="text-xs text-slate-500">{t.importModeOverwriteDesc}</span>
              </button>
              <button 
                  onClick={closeImportFlow}
                  className="w-full py-2 text-sm font-bold text-slate-400 hover:text-slate-600"
              >
                  {t.importCancel}
              </button>
          </div>
      </Modal>

      {/* Import Stage 2: Settings Review */}
      <Modal isOpen={importStage === 'settings-review' && !!tempSettings} onClose={closeImportFlow} title={t.importSettingsTitle}>
          <div className="space-y-4">
              <div className="bg-blue-50 dark:bg-blue-900/20 p-3 rounded-lg flex items-center gap-2">
                  <AlertTriangleIcon className="text-blue-500" size={20} />
                  <p className="text-xs text-blue-600 dark:text-blue-300">
                      {t.importSettingsWarning}
                  </p>
              </div>

              <div className="max-h-[50vh] overflow-y-auto custom-scrollbar space-y-4 pr-1">
                  {tempSettings && (
                    <>
                       <p className="text-xs font-bold text-slate-400 uppercase tracking-wider">{t.importReviewDetails}</p>
                       <ImportReview 
                          settings={tempSettings} 
                          pendingImport={pendingImport} 
                          importSelection={importSelection} 
                          setImportSelection={setImportSelection} 
                          t={t}
                       />
                    </>
                  )}
              </div>

              <div className="flex gap-3 pt-2">
                  <button 
                      onClick={closeImportFlow}
                      className="flex-1 py-2 rounded-lg border border-slate-300 dark:border-slate-600 text-slate-500 font-bold text-sm"
                  >
                      {t.importSkipSettings}
                  </button>
                  <button 
                      onClick={applyImportSettings}
                      className="flex-1 py-2 rounded-lg bg-primary text-white font-bold text-sm hover:opacity-90"
                  >
                      {t.importApplySettings}
                  </button>
              </div>
          </div>
      </Modal>


      {/* Suggest Group Modal (Step 1 of workflow) */}
      <Modal isOpen={groupingQueue.length > 0} onClose={() => handleGroupDecision(false)} title={t.suggestedGroup}>
         {groupingQueue.length > 0 && (
            <div className="space-y-4">
               <p className="text-sm text-slate-500 dark:text-slate-400">{t.suggestedGroupPrompt}</p>
               <div className="neu-concave p-3 rounded-xl">
                  <p className="font-bold text-lg text-center mb-2 text-primary">{groupingQueue[0].title}</p>
                  <p className="text-xs text-slate-400 font-bold mb-1 uppercase tracking-wider">{t.groupContents}</p>
                  <ul className="text-sm text-slate-600 dark:text-slate-300 space-y-1">
                      {groupingQueue[0].subtasks?.map((s, i) => (
                          <li key={i} className="flex items-center gap-2">
                              <span className="w-1 h-1 rounded-full bg-slate-400"></span>
                              {s.title}
                          </li>
                      ))}
                  </ul>
               </div>
               
               <div className="flex gap-3 pt-2">
                   <button 
                     onClick={() => handleGroupDecision(false)}
                     className="flex-1 py-2 rounded-lg border border-slate-300 dark:border-slate-600 text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors font-bold text-sm"
                   >
                     {t.skipGroup}
                   </button>
                   <button 
                     onClick={() => handleGroupDecision(true)}
                     className="flex-1 py-2 rounded-lg bg-primary text-white font-bold text-sm hover:opacity-90 shadow-lg shadow-primary/30"
                   >
                     {t.confirmGroupBtn}
                   </button>
               </div>
            </div>
         )}
      </Modal>

      {/* Batch Decompose Modal (Step 2 of workflow) */}
      <Modal isOpen={longTermBatchQueue.length > 0} onClose={() => { setLongTermBatchQueue([]); setIsProcessing(false); }} title={t.batchReviewTitle}>
         <div className="space-y-4">
            <p className="text-sm text-slate-500 dark:text-slate-400">{t.batchReviewDesc}</p>
            
            <div className="space-y-2 max-h-[50vh] overflow-y-auto custom-scrollbar p-1">
                {longTermBatchQueue.map(task => (
                    <div 
                        key={task.id} 
                        className="neu-flat p-3 rounded-xl flex items-center gap-3 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800/50"
                        onClick={() => {
                              const newSet = new Set(longTermSelectedIds);
                              if (newSet.has(task.id)) newSet.delete(task.id);
                              else newSet.add(task.id);
                              setLongTermSelectedIds(newSet);
                        }}
                    >
                        <Checkbox 
                          checked={longTermSelectedIds.has(task.id)}
                          onChange={() => {}}
                        />
                        <div className="flex-1">
                            <p className="font-bold text-slate-700 dark:text-slate-200">{task.title}</p>
                            <p className="text-xs text-slate-400">
                                {task.quadrant === 1 ? t.q1 : task.quadrant === 2 ? t.q2 : task.quadrant === 3 ? t.q3 : t.q4}
                            </p>
                        </div>
                        <div className="text-yellow-500">
                            <SplitIcon size={18} />
                        </div>
                    </div>
                ))}
            </div>

            <div className="flex gap-3 pt-2">
                <button 
                   onClick={handleSkipBatchDecompose}
                   disabled={isProcessing}
                   className="flex-1 py-3 rounded-xl border border-slate-300 dark:border-slate-600 text-slate-500 font-bold text-sm hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
                >
                   {t.skipBatch}
                </button>
                <button 
                   onClick={handleBatchDecompose}
                   disabled={isProcessing}
                   className="flex-[2] neu-btn py-3 rounded-xl font-bold text-primary flex justify-center items-center gap-2 hover:opacity-90"
                >
                   {isProcessing ? (
                       <>
                         <LoaderIcon className="animate-spin" />
                         {t.processingBatch}
                       </>
                   ) : (
                       <>
                         <SparklesIcon />
                         {t.processBatch} ({longTermSelectedIds.size})
                       </>
                   )}
                </button>
            </div>
         </div>
      </Modal>

      {/* Single Task Decompose Modal (Immediate Feedback) */}
      <Modal isOpen={!!singleDecomposingTask} onClose={() => setSingleDecomposingTask(null)}>
          <div className="flex flex-col items-center justify-center py-8 space-y-4">
             <p className="text-xl font-bold text-slate-700 dark:text-slate-200 text-center">{singleDecomposingTask?.title}</p>
             <LoaderIcon className="animate-spin text-primary" size={48} />
             <p className="text-sm text-slate-500 dark:text-slate-400 font-bold animate-pulse">{t.decomposingSingle}</p>
          </div>
      </Modal>

      {/* Manual Grouping Modal */}
      <Modal isOpen={groupModalOpen} onClose={() => setGroupModalOpen(false)} title={t.confirmGroup}>
         <div className="space-y-4">
            <p className="text-sm text-slate-500">{t.groupingPrompt}</p>
            <div className="flex flex-wrap gap-2 mb-2">
                {Array.from(selectedTaskIds).map(id => {
                    const task = tasks.find(t => t.id === id);
                    return task ? (
                        <span key={id} className="text-xs bg-slate-200 dark:bg-slate-700 px-2 py-1 rounded text-slate-600 dark:text-slate-300 animate-pop-in">
                            {task.title}
                        </span>
                    ) : null;
                })}
            </div>
            <input 
              autoFocus
              type="text"
              value={groupTitleInput}
              onChange={(e) => setGroupTitleInput(e.target.value)}
              placeholder={t.groupTitlePlaceholder}
              onKeyDown={(e) => e.key === 'Enter' && handleConfirmGroup()}
              className="w-full neu-pressed p-3 rounded-xl outline-none bg-transparent text-slate-700 dark:text-slate-200"
            />
            <div className="flex justify-end gap-2">
                 <button 
                   onClick={handleConfirmGroup}
                   className="neu-btn px-4 py-2 rounded-lg text-primary font-bold text-sm"
                 >
                   {t.confirmGroup}
                 </button>
            </div>
         </div>
      </Modal>

    </div>
  );
}
