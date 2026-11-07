import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {title:"AAJ Mock Examination Portal",description:"ALFURQAN ACADEMY JAMA’ARE SS3 Mock Examination"};
export default function RootLayout({children}:{children:React.ReactNode}) {
 return <html lang="en"><body><header className="brand"><h1>ALFURQAN ACADEMY JAMA’ARE</h1><div>SS3 MOCK EXAMINATION PORTAL</div></header>{children}</body></html>;
}