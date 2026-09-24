import { useRef, useEffect } from 'react';

export function WaterfallChart({ dt, dtUpd, dtYtd }) {
  const canvasRef = useRef(null);
  const chartRef = useRef(null);
  const chenh = dtUpd - dt;
  const chenhPos = chenh >= 0;
  const dauNamTy = dt / 1e9;
  const updTy = dtUpd / 1e9;
  const chenhTy = chenh / 1e9;
  const conLaiTy = (dtUpd - (dtYtd || 0)) / 1e9;
  useEffect(() => {
    if (!canvasRef.current) return;
    let cancelled = false;
    import('chart.js/auto').then(({ default: ChartJS }) => {
      if (cancelled || !canvasRef.current) return;
      if (chartRef.current) chartRef.current.destroy();
      const maxVal = Math.max(dauNamTy, updTy) * 1.25;
      const colBlue = '#2a78d6';
      const colGreen = '#10b981';
      const colRed = '#e34948';
      const colPurple = '#7c3aed';
      const dataLabels = [
        dauNamTy.toFixed(1),
        updTy.toFixed(1),
        (chenhPos ? '+' : '') + chenhTy.toFixed(1),
        conLaiTy.toFixed(1),
      ];
      const labelColors = ['#1e293b', '#1e293b', chenhPos ? colGreen : colRed, colPurple];
      chartRef.current = new ChartJS(canvasRef.current, {
        type: 'bar',
        data: {
          labels: ['Đầu năm', 'Update', 'Chênh lệch', 'KH còn lại'],
          datasets: [
            {
              label: 'base',
              data: [0, 0, chenhPos ? dauNamTy : updTy, 0],
              backgroundColor: 'transparent',
              borderWidth: 0,
              barPercentage: 0.5,
            },
            {
              label: 'val',
              data: [dauNamTy, updTy, Math.abs(chenhTy), Math.max(0, conLaiTy)],
              backgroundColor: [colBlue, colBlue, chenhPos ? colGreen : colRed, colPurple],
              borderWidth: 0,
              borderRadius: 3,
              barPercentage: 0.5,
            },
          ],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false }, tooltip: { enabled: false } },
          scales: {
            x: {
              stacked: true,
              grid: { display: false },
              border: { color: '#e1e0d9' },
              ticks: { color: '#898781', font: { size: 11 } },
            },
            y: {
              stacked: true,
              min: 0,
              max: Math.ceil(maxVal / 10) * 10 || 10,
              grid: { color: '#e1e0d9', lineWidth: 0.5 },
              border: { display: false },
              ticks: {
                color: '#898781',
                font: { size: 11 },
                stepSize: Math.ceil(maxVal / 40) * 10 || 10,
              },
            },
          },
          animation: { duration: 500 },
        },
        plugins: [
          {
            id: 'wfConn',
            afterDatasetsDraw(chart) {
              const ctx = chart.ctx;
              const meta = chart.getDatasetMeta(1);
              const baseMeta = chart.getDatasetMeta(0);
              if (meta.data.length < 3) return;
              ctx.save();
              ctx.strokeStyle = '#898781';
              ctx.lineWidth = 1;
              ctx.setLineDash([3, 3]);
              const b0 = meta.data[0],
                b1 = meta.data[1],
                b2 = meta.data[2];
              ctx.beginPath();
              ctx.moveTo(b0.x + b0.width / 2 + 2, b0.y);
              ctx.lineTo(b1.x - b1.width / 2 - 2, b1.y);
              ctx.stroke();
              const connY = chenhPos ? baseMeta.data[2].y : b2.y;
              ctx.beginPath();
              ctx.moveTo(b1.x + b1.width / 2 + 2, connY);
              ctx.lineTo(b2.x - b2.width / 2 - 2, connY);
              ctx.stroke();
              ctx.restore();
            },
          },
          {
            id: 'wfLabels',
            afterDraw(chart) {
              const ctx = chart.ctx;
              const meta = chart.getDatasetMeta(1);
              ctx.save();
              ctx.font = '600 12px -apple-system,BlinkMacSystemFont,sans-serif';
              ctx.textAlign = 'center';
              meta.data.forEach((bar, i) => {
                ctx.fillStyle = labelColors[i];
                ctx.fillText(dataLabels[i], bar.x, bar.y - 6);
              });
              ctx.restore();
            },
          },
        ],
      });
    });
    return () => {
      cancelled = true;
      if (chartRef.current) {
        chartRef.current.destroy();
        chartRef.current = null;
      }
    };
  }, [dauNamTy, updTy, chenhTy, conLaiTy]);
  return (
    <div className="bg-white border border-slate-200 rounded-xl p-3.5 flex flex-col">
      <div className="text-[11px] text-slate-400 mb-2 tracking-wide">
        Phân tích doanh thu kế hoạch (tỷ VNĐ)
      </div>
      <div className="flex-1 min-h-0" style={{ position: 'relative' }}>
        <canvas ref={canvasRef} />
      </div>
    </div>
  );
}

export function Sparkline({ values, color = '#1877f2', width = 90, height = 22 }) {
  if (!values?.length) return null;
  const max = Math.max(...values, 1),
    min = Math.min(...values, 0);
  const range = max - min || 1;
  const step = width / Math.max(1, values.length - 1);
  const points = values
    .map(
      (v, i) =>
        `${i * step},${height - ((v - min) / range) * (height - 2) - 1}`,
    )
    .join(' ');
  return (
    <svg width={width} height={height}>
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
