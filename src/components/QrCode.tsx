import QRCode from "react-qr-code";

interface QrCodeProps {
  value: string;
  size?: number;
  title?: string;
}

/** High-contrast QR for TV distance scanning (white pad, dark modules). */
export function QrCode({ value, size = 196, title = "Quick Connect QR code" }: QrCodeProps) {
  const trimmed = value.trim();
  if (!trimmed) return null;

  return (
    <div className="quick-connect-qr" role="img" aria-label={title}>
      <QRCode value={trimmed} size={size} bgColor="#ffffff" fgColor="#10151c" level="M" />
    </div>
  );
}
