# 21. 좋아요·즐겨찾기 부탁 창

2026-10-18 사용자 요청("좋아요나 즐겨찾기 보상")을 검토해 **보상 없는 부탁 창**으로 만들었다.

## 왜 보상이 없나

- **규칙 위험**: Roblox 개발자 포럼의 공통 의견은 "좋아요(평가)에 보상을 주면 규칙 위반"이다. Community Rules의 "상품을 걸고 홍보하지 말 것" 조항을 근거로 든다. 즐겨찾기 보상은 의견이 갈린다. 공식 문서에서 명시적인 허용·금지 문구는 찾지 못했다. 수익을 낼 게임이 모더레이션 위험을 질 이유가 없어서 보상을 빼기로 했다.
- **확인 불가**: 좋아요 여부는 게임 안에서 읽을 수 없다. 즐겨찾기 확인 API(`AvatarEditorService:GetFavoriteAsync`)는 아바타 아이템·번들용이고, 클라이언트에서 도는 확인이라 조작도 쉽다.
- **안전한 대안**: 그룹 가입 보상은 서버에서 확인할 수 있고(`IsInGroupAsync`) 허용된다는 의견이 일반적이다. 그룹이 생기면 추가한다.

## 동작 (client/RatePrompt.luau)

- 계정당 한 번만 띄운다. 띄우면 서버에 `data.rateAsked = true`를 저장한다(Remote `RateAsked`).
- 접속 10분이 지난 뒤 처음 오는 기분 좋은 순간에 띄운다. 드문 변이 공개, 기록 경신, 도감 마일스톤 배너가 끝날 즈음(4.5초 뒤)이다.
- 그런 순간이 없으면 접속 20분에 띄운다.
- 문구: "Enjoying the factory? Tap 👍 Like and ⭐ Favorite on the game page! It helps us add new cubes and events." 버튼은 OK! 하나.
- Studio 확인: 창 표시, 서버 스냅숏 `rateAsked = true`.
