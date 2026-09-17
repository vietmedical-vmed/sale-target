import React from 'react';

export class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      error: null,
    };
  }
  static getDerivedStateFromError(error) {
    return {
      error,
    };
  }
  componentDidCatch(error, info) {
    console.error('[react error]', error, info);
  }
  render() {
    if (this.state.error) {
      return (
        <div
          style={{
            padding: 32,
            maxWidth: 600,
            margin: '80px auto',
            background: '#fef2f2',
            borderRadius: 8,
            border: '1px solid #fecaca',
          }}
        >
          <h2
            style={{
              color: '#991b1b',
              marginTop: 0,
            }}
          >
            ⚠ Lỗi UI
          </h2>
          <pre
            style={{
              whiteSpace: 'pre-wrap',
              color: '#7f1d1d',
              background: '#fff',
              padding: 12,
              borderRadius: 6,
              fontSize: 12,
            }}
          >
            {String(this.state.error.stack || this.state.error)}
          </pre>
          <button
            onClick={() => location.reload()}
            style={{
              marginTop: 12,
              padding: '8px 16px',
              background: '#fa383e',
              color: '#fff',
              border: 'none',
              borderRadius: 6,
              cursor: 'pointer',
            }}
          >
            Tải lại trang
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
