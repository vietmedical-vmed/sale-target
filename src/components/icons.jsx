
const Ic =
  (paths) =>
  ({ size = 16, className = '', ...rest }) => (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      {...rest}
    >
      {paths.map((d, i) => (
        <path key={i} d={d} />
      ))}
    </svg>
  );

export const Search = Ic([
  'm21 21-4.34-4.34',
  'M11 17a6 6 0 1 0 0-12 6 6 0 0 0 0 12Z',
]);
export const Download = Ic([
  'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4',
  'M7 10l5 5 5-5',
  'M12 15V3',
]);
export const Check = Ic(['M20 6 9 17l-5-5']);
export const Loader2 = Ic(['M21 12a9 9 0 1 1-6.219-8.56']);
export const AlertCircle = Ic([
  'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z',
  'M12 8v4',
  'M12 16h.01',
]);
export const ChevronDown = Ic(['m6 9 6 6 6-6']);
export const ChevronUp = Ic(['m6 15 6-6 6 6']);
export const ChevronRight = Ic(['m9 6 6 6-6 6']);
export const RefreshCw = Ic([
  'M3 12a9 9 0 0 1 15-6.7L21 8',
  'M21 3v5h-5',
  'M21 12a9 9 0 0 1-15 6.7L3 16',
  'M3 21v-5h5',
]);
export const LockIcon = Ic([
  'M19 11H5a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7a2 2 0 0 0-2-2z',
  'M7 11V7a5 5 0 0 1 10 0v4',
]);
export const LogOut = Ic([
  'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4',
  'm16 17 5-5-5-5',
  'M21 12H9',
]);
export const User = Ic([
  'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2',
  'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
]);
export const Package = Ic([
  'm7.5 4.27 9 5.15',
  'M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z',
  'M3.27 6.96 12 12.01l8.73-5.05',
  'M12 22.08V12',
]);
export const Eye = Ic([
  'M2.06 12.35a1 1 0 0 1 0-.7 10.5 10.5 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.5 10.5 0 0 1-19.88 0Z',
  'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
]);
export const EyeOff = Ic([
  'M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68',
  'M6.61 6.61A13.5 13.5 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61',
  'M14.12 14.12A3 3 0 1 1 9.88 9.88',
  'm2 2 20 20',
]);
export const Trash2 = Ic([
  'M3 6h18',
  'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2',
  'M10 11v6',
  'M14 11v6',
]);
export const Plus = Ic(['M5 12h14', 'M12 5v14']);
export const XIcon = Ic(['M18 6 6 18', 'm6 6 12 12']);
export const UserPlus = Ic([
  'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2',
  'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  'M19 8v6',
  'M22 11h-6',
]);
export const Clock = Ic([
  'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z',
  'M12 6v6l4 2',
]);
export const Filter = Ic(['M22 3H2l8 9.46V19l4 2v-8.54L22 3z']);
export const Settings = Ic([
  'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z',
  'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
]);
