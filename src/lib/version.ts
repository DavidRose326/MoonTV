// src/lib/version.ts
/* eslint-disable @typescript-eslint/no-unused-vars */
'use client';

// 固定的当前版本号
const CURRENT_VERSION = '20250731021807';

export enum UpdateStatus {
  HAS_UPDATE = 'has_update',
  NO_UPDATE = 'no_update',
  FETCH_FAILED = 'fetch_failed',
}

/**
 * 安全移除：不再发起网络请求，永远返回无更新状态
 */
export async function checkForUpdates(): Promise<UpdateStatus> {
  // 直接返回无更新，不执行 fetch
  return UpdateStatus.NO_UPDATE;
}

export { CURRENT_VERSION };
