import React, { useState, useEffect } from 'react';
import { Task, QuadrantType, AIConfig, AIProvider, AppSettings, InputMode, Board, ThemeColor, SubTask, ExportData } from './types';
import { analyzeTasks, decomposeTasksBatch } from './services/aiService';
import { translations } from './translations';
import { 
  SparklesIcon, SettingsIcon, PlusIcon, 
  AlertTriangleIcon, LoaderIcon, SplitIcon, TrashIcon,
  MoonIcon, SunIcon, GlobeIcon, MonitorIcon, LayersIcon, DownloadIcon, UploadIcon
} from './components/Icons';

// UI Components
import { Modal } from './components/ui/Modal';
import { Checkbox } from './components/ui/Checkbox';

// Feature Components
import { Quadrant } from './components/Quadrant';
import { InputArea } from './components/InputArea';
import { SettingsControls } from './components/SettingsControls';
import { ImportReview } from './components/ImportReview';

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
  const [boardMenuOpen, setBoardMenuOpen] = useState(false);
  const [renameBoardId, setRenameBoardId] = useState<string | null>(null);
  const [newBoardName, setNewBoardName] = useState('');
  
  // Confirmation Modal State
  const [confirmationState, setConfirmationState] = useState<{
      type: 'deleteTask' | 'deleteBoard' | 'clearQuadrant';
      id: string; // Task ID, Board ID, or Quadrant ID (as string)
      title?: string;
  } | null>(null);

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

  // Edit State
  const [editingTask, setEditingTask] = useState<{ task: Task, subId?: string } | null>(null);
  const [editDateInput, setEditDateInput] = useState('');

  // Config & Settings State
  const [aiConfig, setAiConfig] = useState<AIConfig>({
    provider: AIProvider.Gemini,
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
    urgencyThresholdDays: 3
  });

  // Helper for translations
  const t = translations[appSettings.language];

  // --- Effects ---

  useEffect(() => {
    const savedConfig = localStorage.getItem('matrixflow-config');
    if (savedConfig) setAiConfig(JSON.parse(savedConfig));

    const savedSettings = localStorage.getItem('matrixflow-settings');
    if (savedSettings) {
      const parsed = JSON.parse(savedSettings);
      setAppSettings({
         ...parsed,
         autoGroupAI: parsed.autoGroupAI ?? false,
         autoDecomposeAI: parsed.autoDecomposeAI ?? false,
         autoCompleteParent: parsed.autoCompleteParent ?? false,
         suppressGroupPrompt: parsed.suppressGroupPrompt ?? false,
         suppressLongTermPrompt: parsed.suppressLongTermPrompt ?? false,
         urgencyThresholdDays: parsed.urgencyThresholdDays ?? 3
      });
      setInputMode(parsed.defaultInputMode); 
    }

    const savedBoards = localStorage.getItem('matrixflow-boards');
    const savedTasks = localStorage.getItem('matrixflow-tasks');
    
    let loadedBoards: Board[] = [];
    let loadedTasks: Task[] = [];

    if (savedBoards) {
      loadedBoards = JSON.parse(savedBoards);
    }
    
    if (savedTasks) {
      const rawTasks = JSON.parse(savedTasks);
      if (rawTasks.length > 0 && !rawTasks[0].boardId) {
        const defaultBoardId = crypto.randomUUID();
        if (loadedBoards.length === 0) {
          loadedBoards.push({ id: defaultBoardId, name: t.defaultBoardName, createdAt: Date.now() });
        }
        const targetBoardId = loadedBoards[0]?.id || defaultBoardId;
        loadedTasks = rawTasks.map((task: any) => ({ ...task, boardId: targetBoardId }));
      } else {
        loadedTasks = rawTasks;
      }
    }

    if (loadedBoards.length === 0) {
      const newBoard = { id: crypto.randomUUID(), name: t.defaultBoardName, createdAt: Date.now() };
      loadedBoards.push(newBoard);
    }

    setBoards(loadedBoards);
    setTasks(loadedTasks);
    setActiveBoardId(loadedBoards[0].id);

  }, []);

  // Save changes
  useEffect(() => { if (tasks.length > 0) localStorage.setItem('matrixflow-tasks', JSON.stringify(tasks)); }, [tasks]);
  useEffect(() => { if (boards.length > 0) localStorage.setItem('matrixflow-boards', JSON.stringify(boards)); }, [boards]);
  useEffect(() => { localStorage.setItem('matrixflow-config', JSON.stringify(aiConfig)); }, [aiConfig]);
  useEffect(() => { localStorage.setItem('matrixflow-settings', JSON.stringify(appSettings)); }, [appSettings]);

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

  // --- Handlers ---

  const activeTasks = tasks.filter(t => t.boardId === activeBoardId);
  const activeBoard = boards.find(b => b.id === activeBoardId);

  const openAddModal = () => {
    setInputMode(appSettings.defaultInputMode);
    setAddModalOpen(true);
  };

  const handleDragStart = (e: React.DragEvent, task: Task) => {
    e.dataTransfer.setData('taskId', task.id);
    e.dataTransfer.effectAllowed = 'move';
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  };

  const handleDrop = (e: React.DragEvent, targetQuadrant: QuadrantType) => {
    e.preventDefault();
    const taskId = e.dataTransfer.getData('taskId');
    setTasks(prev => prev.map(t => 
      t.id === taskId ? { ...t, quadrant: targetQuadrant } : t
    ));
  };

  // --- Deletion Logic with Confirmation ---

  const handleDeleteTaskTrigger = (id: string) => {
      setConfirmationState({ type: 'deleteTask', id });
  };
  
  const handleClearQuadrantTrigger = (type: QuadrantType) => {
      setConfirmationState({ type: 'clearQuadrant', id: String(type) });
  };
  
  const handleDeleteBoardTrigger = (id: string) => {
     if (boards.length <= 1) return; 
     setConfirmationState({ type: 'deleteBoard', id });
  };

  const executeConfirmAction = () => {
      if (!confirmationState) return;
      const { type, id } = confirmationState;

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
      }

      setConfirmationState(null);
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
  const executeBatchDecompose = async (tasksToDecompose: Task[]) => {
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
          alert(t.error);
      }
  };

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
      alert(`${t.error}: ` + (err instanceof Error ? err.message : String(err)));
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
  const handleManualDecompose = async (task: Task) => {
      setSingleDecomposingTask(task);
      try {
         await executeBatchDecompose([task]);
      } catch (err) {
         console.error(err);
         alert(t.error);
      } finally {
         setSingleDecomposingTask(null);
      }
  };

  const handleManualAdd = () => {
    if (!inputText.trim()) return;
    
    const newTask: Task = {
      id: crypto.randomUUID(),
      boardId: activeBoardId,
      title: inputText,
      quadrant: QuadrantType.Do, 
      isLongTerm: false,
      completed: false,
      createdAt: Date.now(),
    };
    setTasks(prev => [newTask, ...prev]);
    setInputText('');
    if (addModalOpen) setAddModalOpen(false);
  };

  // General Update Handler (for subtask toggles, edits, drag drop)
  const handleTaskUpdate = (updatedTask: Task) => {
    // Auto-Complete Parent Logic (When Subtasks are toggled)
    if (appSettings.autoCompleteParent && updatedTask.subtasks && updatedTask.subtasks.length > 0) {
        const total = updatedTask.subtasks.length;
        const completed = updatedTask.subtasks.filter(s => s.completed).length;
        
        if (total > 0 && total === completed) {
             updatedTask.completed = true;
        } else if (updatedTask.completed && total !== completed) {
             // Optional: Uncheck parent if a subtask is unchecked
             updatedTask.completed = false;
        }
    }

    setTasks(prev => prev.map(t => t.id === updatedTask.id ? updatedTask : t));
  };

  // Cascading Parent Checkbox Logic
  const handleParentCheck = (task: Task) => {
    const newStatus = !task.completed;
    
    // Create new subtasks array with forced status
    const updatedSubtasks = task.subtasks?.map(s => ({
      ...s,
      completed: newStatus
    }));

    const newTask = {
      ...task,
      completed: newStatus,
      subtasks: updatedSubtasks
    };

    // We bypass handleTaskUpdate's internal auto-complete check because we are forcing consistency here.
    // If we used handleTaskUpdate, the logic might revert based on old subtask states before the update propagates.
    setTasks(prev => prev.map(t => t.id === newTask.id ? newTask : t));
  };

  // Selection & Grouping Handlers
  const toggleSelectionMode = () => {
    setIsSelectionMode(!isSelectionMode);
    setSelectedTaskIds(new Set());
  };

  const handleToggleSelect = (id: string) => {
    const newSet = new Set(selectedTaskIds);
    if (newSet.has(id)) newSet.delete(id);
    else newSet.add(id);
    setSelectedTaskIds(newSet);
  };

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

  // Edit Handlers
  const openEditModal = (task: Task, subId?: string) => {
      setEditingTask({ task, subId });
      let currentDeadline: number | undefined;
      if (subId && task.subtasks) {
          const sub = task.subtasks.find(s => s.id === subId);
          currentDeadline = sub?.deadline;
      } else {
          currentDeadline = task.deadline;
      }
      if (currentDeadline) {
          setEditDateInput(new Date(currentDeadline).toISOString().split('T')[0]);
      } else {
          setEditDateInput('');
      }
  };

  const saveEdit = () => {
      if (!editingTask) return;
      const timestamp = editDateInput ? new Date(editDateInput).getTime() : undefined;
      if (editingTask.subId) {
           const updatedSubs = (editingTask.task.subtasks || []).map(s => 
              s.id === editingTask.subId ? { ...s, deadline: timestamp } : s
           );
           handleTaskUpdate({ ...editingTask.task, subtasks: updatedSubs });
      } else {
          handleTaskUpdate({ ...editingTask.task, deadline: timestamp });
      }
      setEditingTask(null);
  };

  // Board Management Handlers
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
    setBoardMenuOpen(false);
  };

  // Deletion logic moved to executeConfirmAction
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

              // Basic Schema Validation
              if (!Array.isArray(json.boards) || !Array.isArray(json.tasks)) {
                  alert(t.importError);
                  return;
              }
              
              setPendingImport(json);
              // Initialize import selection with all available keys including granular automation settings
              setImportSelection(new Set([
                'language', 'theme', 'themeColor', 'inputMode', 'aiProvider', 
                'autoDecomposeAI', 'suppressLongTermPrompt', 'autoGroupAI', 'suppressGroupPrompt', 'autoCompleteParent', 'urgencyThresholdDays'
              ]));
              
              // Step 1: Ask User Mode
              setImportStage('mode-select');

          } catch (err) {
              console.error(err);
              alert(t.importError);
          } finally {
              e.target.value = '';
          }
      };
      reader.readAsText(file);
  };

  const executeImportTasks = (mode: 'merge' | 'overwrite') => {
      if (!pendingImport) return;

      if (mode === 'overwrite') {
          setBoards(pendingImport.boards);
          setTasks(pendingImport.tasks);
          // Set active board to first imported or defaults
          if (pendingImport.boards.length > 0) setActiveBoardId(pendingImport.boards[0].id);
      } else {
          // Merge: Append tasks. Merge boards by ID, else add.
          const existingBoardIds = new Set(boards.map(b => b.id));
          const newBoards = pendingImport.boards.filter(b => !existingBoardIds.has(b.id));
          
          setBoards(prev => [...prev, ...newBoards]);
          setTasks(prev => [...prev, ...pendingImport.tasks]);
      }

      // Proceed to Step 2: Settings
      if (pendingImport.settings) {
          setTempSettings(pendingImport.settings);
          setImportStage('settings-review');
      } else {
          closeImportFlow();
          alert(t.importSuccess);
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
              
              // Granular Automation Settings
              if (importSelection.has('autoDecomposeAI')) next.autoDecomposeAI = tempSettings.autoDecomposeAI;
              if (importSelection.has('suppressLongTermPrompt')) next.suppressLongTermPrompt = tempSettings.suppressLongTermPrompt;
              if (importSelection.has('autoGroupAI')) next.autoGroupAI = tempSettings.autoGroupAI;
              if (importSelection.has('suppressGroupPrompt')) next.suppressGroupPrompt = tempSettings.suppressGroupPrompt;
              if (importSelection.has('autoCompleteParent')) next.autoCompleteParent = tempSettings.autoCompleteParent;
              if (importSelection.has('urgencyThresholdDays')) next.urgencyThresholdDays = tempSettings.urgencyThresholdDays;
              
              return next;
          });
      }
      if (pendingImport?.aiConfig && importSelection.has('aiProvider')) {
          setAiConfig(pendingImport.aiConfig);
      }
      closeImportFlow();
      alert(t.importSuccess);
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
               onClick={() => setBoardMenuOpen(!boardMenuOpen)}
               className="flex items-center gap-2 font-bold text-lg text-slate-700 dark:text-slate-200 hover:text-primary transition-colors"
             >
               {activeBoard?.name || t.defaultBoardName}
               <svg className={`w-4 h-4 transition-transform duration-300 ${boardMenuOpen ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
             </button>

             {boardMenuOpen && (
               <div className="absolute top-full left-0 mt-2 w-64 neu-flat rounded-xl p-2 animate-slide-down origin-top z-50 shadow-xl">
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
                            onClick={() => { setActiveBoardId(board.id); setBoardMenuOpen(false); }}
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

            <button 
              onClick={() => setSettingsOpen(true)}
              className="neu-btn p-3 rounded-full text-slate-500 dark:text-slate-400 hover:text-primary transition-colors active:scale-95"
            >
              <SettingsIcon />
            </button>
        </div>
      </header>

      {/* --- Main Content --- */}
      <div className="flex-1 flex flex-col md:flex-row gap-6 px-4 md:px-8 pb-6 md:pb-8 overflow-hidden">
        
        {/* Desktop Input Panel (Hidden on Mobile) */}
        <div className="hidden md:block w-80 flex-none flex flex-col gap-4">
           <div className="neu-flat rounded-2xl p-6 flex-1 flex flex-col">
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
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Do)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
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
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Plan)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
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
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Delegate)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
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
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Eliminate)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
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

      {/* Mobile FAB (Hidden on Desktop) */}
      <button 
        onClick={openAddModal}
        className="md:hidden absolute bottom-8 right-6 w-14 h-14 rounded-full bg-primary text-white shadow-lg shadow-primary/40 flex items-center justify-center active:scale-90 transition-transform z-30 animate-pop-in"
      >
        <PlusIcon size={28} />
      </button>

      {/* --- Modals --- */}

      {/* Neumorphic Confirmation Modal (Restyled) */}
      <Modal 
          isOpen={!!confirmationState} 
          onClose={() => setConfirmationState(null)} 
          title={
              confirmationState?.type === 'deleteTask' ? t.deleteTaskTitle :
              confirmationState?.type === 'deleteBoard' ? t.deleteBoardTitle :
              t.clearQuadrantTitle
          }
      >
          <div className="space-y-6">
              {/* Neumorphic Concave Alert Box */}
              <div className="neu-concave p-5 rounded-xl flex items-center gap-4 text-red-500">
                  <div className="p-3 bg-red-100 dark:bg-red-900/20 rounded-full flex-none">
                     <AlertTriangleIcon size={28} className="animate-pulse" />
                  </div>
                  <p className="text-sm font-bold text-slate-600 dark:text-slate-300">
                      {confirmationState?.type === 'deleteTask' ? t.deleteTaskConfirm :
                       confirmationState?.type === 'deleteBoard' ? t.confirmDeleteBoard :
                       t.confirmClearQuadrant}
                  </p>
              </div>
              
              <div className="flex gap-4">
                  <button 
                      onClick={() => setConfirmationState(null)}
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
            <div className="flex gap-2 mb-3">
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.Gemini }))}
                className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${aiConfig.provider === AIProvider.Gemini ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
              >
                Gemini
              </button>
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.Custom }))}
                className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${aiConfig.provider === AIProvider.Custom ? 'neu-pressed text-green-500' : 'neu-flat text-slate-500'}`}
              >
                Custom API
              </button>
            </div>

            {aiConfig.provider === AIProvider.Custom && (
              <div className="space-y-3 p-3 neu-concave rounded-xl animate-fade-in">
                <div>
                  <label className="text-xs font-bold text-slate-400">{t.customBaseUrl}</label>
                  <input 
                    type="text" 
                    value={aiConfig.customBaseUrl}
                    onChange={(e) => setAiConfig(c => ({ ...c, customBaseUrl: e.target.value }))}
                    className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slate-400">{t.customApiKey}</label>
                  <input 
                    type="password" 
                    value={aiConfig.customApiKey}
                    onChange={(e) => setAiConfig(c => ({ ...c, customApiKey: e.target.value }))}
                    className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slate-400">{t.customModel}</label>
                  <input 
                    type="text" 
                    value={aiConfig.customModel}
                    onChange={(e) => setAiConfig(c => ({ ...c, customModel: e.target.value }))}
                    className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                  />
                </div>
              </div>
            )}
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
      <Modal isOpen={!!singleDecomposingTask} onClose={() => {}} hideClose={true}>
          <div className="flex flex-col items-center justify-center py-8 space-y-4">
             <p className="text-xl font-bold text-slate-700 dark:text-slate-200">{singleDecomposingTask?.title}</p>
             <LoaderIcon className="animate-spin text-primary" size={48} />
             <p className="text-sm text-slate-500 dark:text-slate-400 font-bold animate-pulse">{t.decomposingSingle}</p>
          </div>
      </Modal>

      {/* Task/Subtask Edit Modal */}
      <Modal isOpen={!!editingTask} onClose={() => setEditingTask(null)} title={editingTask?.subId ? t.editSubtask : t.editTask}>
         <div className="space-y-4">
             <div>
                 <label className="block text-xs font-bold text-slate-500 mb-1">{t.setDeadline}</label>
                 <input 
                   type="date" 
                   value={editDateInput}
                   onChange={(e) => setEditDateInput(e.target.value)}
                   className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-2 text-lg outline-none text-slate-700 dark:text-slate-200 font-mono"
                 />
             </div>
             <div className="flex justify-end gap-2 mt-4">
                 <button 
                   onClick={saveEdit}
                   className="neu-btn px-4 py-2 rounded-lg text-primary font-bold text-sm"
                 >
                   {t.addSingleBtn}
                 </button>
             </div>
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