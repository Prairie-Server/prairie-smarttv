import { describe, expect, it } from "vitest";
import { isPrivateOrLocalHost, validateServerUrl } from "./serverUrl";

describe("isPrivateOrLocalHost", () => {
  it("accepts loopback and RFC1918 IPv4", () => {
    expect(isPrivateOrLocalHost("127.0.0.1")).toBe(true);
    expect(isPrivateOrLocalHost("10.0.0.5")).toBe(true);
    expect(isPrivateOrLocalHost("192.168.1.10")).toBe(true);
    expect(isPrivateOrLocalHost("172.16.0.2")).toBe(true);
  });

  it("accepts link-local IPv4 and .local mDNS", () => {
    expect(isPrivateOrLocalHost("169.254.2.3")).toBe(true);
    expect(isPrivateOrLocalHost("prairie.local")).toBe(true);
  });

  it("accepts loopback and link-local IPv6", () => {
    expect(isPrivateOrLocalHost("::1")).toBe(true);
    expect(isPrivateOrLocalHost("fe80::1")).toBe(true);
  });

  it("rejects public hosts", () => {
    expect(isPrivateOrLocalHost("prairie.example.com")).toBe(false);
    expect(isPrivateOrLocalHost("8.8.8.8")).toBe(false);
    expect(isPrivateOrLocalHost("172.32.0.2")).toBe(false);
    expect(isPrivateOrLocalHost("10.attacker.example")).toBe(false);
  });
});

describe("validateServerUrl", () => {
  it("accepts normalized https URLs", () => {
    const result = validateServerUrl(" https://prairie.example.com/// ");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.url).toBe("https://prairie.example.com");
  });

  it("rejects credentials", () => {
    const result = validateServerUrl("https://user:pass@prairie.example.com");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.message).toMatch(/credentials/i);
  });

  it("allows HTTP only for private/LAN hosts", () => {
    for (const url of [
      "http://192.168.1.10:8096",
      "http://10.0.0.5",
      "http://172.16.0.2",
      "http://127.0.0.1:8096",
      "http://localhost:8096",
      "http://prairie.local",
      "http://[::1]:8096",
      "http://169.254.2.3:8096",
    ]) {
      const result = validateServerUrl(url);
      if (!result.ok) {
        throw new Error(`${url} should be allowed for HTTP, got: ${result.message}`);
      }
    }
  });

  it("rejects public HTTP hosts", () => {
    for (const url of [
      "http://prairie.example.com",
      "http://10.attacker.example",
      "http://192.168.attacker.example",
      "http://172.16.attacker.example",
      "http://172.32.0.2",
      "http://8.8.8.8",
    ]) {
      const result = validateServerUrl(url);
      expect(result.ok).toBe(false);
    }
  });

  it("rejects invalid urls", () => {
    expect(validateServerUrl("https://").ok).toBe(false);
    expect(validateServerUrl("https://#fragment").ok).toBe(false);
    expect(validateServerUrl("https://?server=x").ok).toBe(false);
  });

  it("rejects empty, non-http(s), and empty-host inputs", () => {
    const empty = validateServerUrl("   ");
    expect(empty.ok).toBe(false);
    if (!empty.ok) expect(empty.message).toMatch(/Prairie server URL/i);

    const ftp = validateServerUrl("ftp://prairie.example.com");
    expect(ftp.ok).toBe(false);
    if (!ftp.ok) expect(ftp.message).toMatch(/http or https/i);

    // URL may parse, but hostname can still be empty for some authority-less forms.
    const noHost = validateServerUrl("https:///");
    expect(noHost.ok).toBe(false);
  });

  it("treats bracketed IPv6 hosts as private/local when applicable", () => {
    expect(isPrivateOrLocalHost("[::1]")).toBe(true);
    expect(isPrivateOrLocalHost("[fe80::abcd]")).toBe(true);
    expect(isPrivateOrLocalHost("")).toBe(false);
  });
});
