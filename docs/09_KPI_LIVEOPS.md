# 09. KPI와 라이브옵스

## 1. RFY 신호 ↔ 우리 지표 ↔ 계측

| RFY 신호 (02) | 우리 지표 | 계측 (AnalyticsService) | 1차 목표 (출시 4주) |
|---|---|---|---|
| Play-through rate | 노출 대비 플레이 | Creator Analytics > Acquisition | 장르 중앙값 이상 (첫 2주 실측 후 확정) |
| 첫 플레이 이탈률 <60s | 60초 내 이탈 비율 | 퍼널 `FTUE`: spawn→first_merge→first_purchase→first_hatch | first_merge 도달 95%, first_purchase 80% |
| 플레이 일수 D1/D2-7/D8-28 | D1/D7/D30 리텐션 | Creator Analytics Retention | D1 ≥ 25%, D7 ≥ 8% (가정, 실측 후 조정) |
| 플레이 시간 (60분 상한) | 일 평균 세션 시간 | 세션 이벤트 | 20~40분 |
| 의도적 동반 플레이 | 협동 세션 비율 | `TeamService` 커스텀 이벤트 | 10% |
| 지출 일수 / Robux | 결제 전환, ABPDAU | 경제 이벤트 + Monetization 대시보드 | 전환 1.5%, ABPDAU ≥ 1.5 R$ |

- 경제 이벤트: 모든 현금·젬 증감을 `EconomyService` 한 곳에서 `LogEconomyEvent`(source/sink 구분).
- 진행 이벤트: 등급 최초 달성, 리버스, 도감 줄 완성 → `LogProgressionEvent`.
- 목표치는 장르 벤치마크가 없어 **가정값**. 첫 2주 실측 후 이 표를 교체한다.

## 2. 주간 리포트 (에이전트 자동 작성)
- 위 표의 지난주/이번주 값, 노출 제한 배너 여부, 상위 이탈 퍼널 단계, 매출 상위 상품, 에러 리포트 상위 5개.
- 각 하락 신호마다 "가설 1줄 + 다음 업데이트 대응 1줄".

## 3. 업데이트 주기
| 주기 | 내용 | 근거 |
|---|---|---|
| 매주 | 변이 1종 또는 장식 세트, 밸런스 패치, 버그 수정 | 경쟁작 개선 속도 > 내 개선이면 노출 감소 [S2]; 히트작은 주간 업데이트 [S17] |
| 격주 주말 | 이벤트(2배 부화, 관리자 이벤트) | 재방문 스파이크 |
| 시즌(6주) | 패스 갱신, 새 바이옴 | 반복 매출 |
| 월 | Managed pricing 결과 검토, A/B(아이콘·썸네일) | PTR |

## 4. 실험
- 썸네일/아이콘: Roblox 썸네일 개인화·실험 기능 사용, 항상 **실제 화면 기반**(02 §2).
- 인게임: Open Cloud Experiments 또는 자체 플래그(`Config` + 사용자 해시). 한 번에 한 변수.
