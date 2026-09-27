
import React from 'react';

// Crash screen shown when the React tree fails to mount (e.g. unreadable localStorage).
// Lives outside App so it cannot use translations; language picked from the browser.
const DICT = {
  zh: {
    title: '应用启动出错',
    desc: '本地数据可能已损坏。可以清除本地数据后重试（将删除所有任务板、任务与设置），或先尝试重新加载。',
    retry: '重新加载',
    reset: '清除本地数据并重载',
  },
  ja: {
    title: 'アプリの起動エラー',
    desc: 'ローカルデータが破損している可能性があります。ローカルデータを消去して再試行（すべてのボード・タスク・設定を削除）するか、再読み込みをお試しください。',
    retry: '再読み込み',
    reset: 'ローカルデータを消去して再読み込み',
  },
  en: {
    title: 'Something went wrong',
    desc: 'Local data may be corrupted. Clear local data and retry (this deletes all boards, tasks and settings), or try reloading first.',
    retry: 'Reload',
    reset: 'Clear local data and reload',
  },
} as const;

const pickDict = () => {
  const lang = navigator.language || 'en';
  if (lang.startsWith('zh')) return DICT.zh;
  if (lang.startsWith('ja')) return DICT.ja;
  return DICT.en;
};

interface ErrorBoundaryProps {
  children: React.ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends React.Component<ErrorBoundaryProps, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('MatrixFlow AI crashed:', error, info.componentStack);
  }

  private handleReset = () => {
    ['matrixflow-tasks', 'matrixflow-boards', 'matrixflow-config', 'matrixflow-settings']
      .forEach(key => localStorage.removeItem(key));
    window.location.reload();
  };

  render() {
    if (!this.state.error) return this.props.children;

    const d = pickDict();
    return (
      <div className="min-h-screen flex items-center justify-center p-6 bg-[#efeeee] text-slate-700 font-sans">
        <div className="max-w-md w-full rounded-2xl bg-white shadow-xl p-8 space-y-4">
          <h1 className="text-xl font-bold text-red-500">{d.title}</h1>
          <p className="text-sm text-slate-600 leading-relaxed">{d.desc}</p>
          <div className="flex gap-3 pt-2">
            <button
              onClick={() => window.location.reload()}
              className="flex-1 py-2.5 rounded-xl border border-slate-300 text-slate-600 font-bold text-sm hover:bg-slate-50 transition-colors"
            >
              {d.retry}
            </button>
            <button
              onClick={this.handleReset}
              className="flex-1 py-2.5 rounded-xl bg-red-500 text-white font-bold text-sm hover:bg-red-600 transition-colors"
            >
              {d.reset}
            </button>
          </div>
        </div>
      </div>
    );
  }
}
