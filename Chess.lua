-- ============================================================
-- WoW Chess Addon v5.1 for WotLK 3.3.5a
-- English base (Spanish auto-applies only on esES/esMX clients).
-- Chrome-style tabs with a "+" button, empty board on open,
-- Escape toggle, arena "gates open" auto-minimize, mate-in-N
-- indicator, undo vs AI, opponent name display, agreed PvP
-- restart, rematch offer, minimap move alert, aligned history.
-- ============================================================

local ADDON_NAME = "Chess"
local PREFIX     = "WoWChess"
local SQ         = 56
local MAX_GAMES  = 5      -- maximum number of simultaneous game tabs
local TAB_H      = 22

local format = string.format

local L = ChessLocale or setmetatable({}, { __index = function(_, k) return k end })

_G.ChessAddon = _G.ChessAddon or {}
local API = _G.ChessAddon

-- ============================================================
-- SAVEDVARIABLES
-- ChessDB = { history={}, games={}, activeIdx, openTabs, settings={} }
-- ============================================================
local DB

-- ============================================================
-- DIFFICULTIES
-- ============================================================
local DIFFICULTIES = {
    [1] = { name=L["DIFF_NOVICE"], color="88FF88", desc=L["DIFF_NOVICE_DESC"], mode="random",  depth=0 },
    [2] = { name=L["DIFF_EASY"],   color="88CCFF", desc=L["DIFF_EASY_DESC"],   mode="greedy",  depth=0 },
    [3] = { name=L["DIFF_NORMAL"], color="FFFF88", desc=L["DIFF_NORMAL_DESC"], mode="eval",    depth=0 },
    [4] = { name=L["DIFF_HARD"],   color="FFAA44", desc=L["DIFF_HARD_DESC"],   mode="minimax", depth=2 },
    [5] = { name=L["DIFF_EXPERT"], color="FF4444", desc=L["DIFF_EXPERT_DESC"], mode="minimax", depth=3, qsearch=true },
}
local defaultDiff = 3

-- ============================================================
-- TEXTURES
-- ============================================================
local PIECE_TEX_BASE = "Interface\\AddOns\\Chess\\Textures\\"
local function getPieceTex(piece)
    if not piece then return nil end
    local cl=piece:sub(1,1); local pt=piece:sub(2)
    if cl=="w" then return PIECE_TEX_BASE.."white\\"..pt:upper()
    else             return PIECE_TEX_BASE.."black\\"..pt:lower() end
end

-- ============================================================
-- EVALUATION TABLES
-- ============================================================
local PVAL = { P=100, N=320, B=330, R=500, Q=900, K=20000 }
local PST = {
    P={{0,0,0,0,0,0,0,0},{50,50,50,50,50,50,50,50},{10,10,20,30,30,20,10,10},
       {5,5,10,25,25,10,5,5},{0,0,0,20,20,0,0,0},{5,-5,-10,0,0,-10,-5,5},
       {5,10,10,-20,-20,10,10,5},{0,0,0,0,0,0,0,0}},
    N={{-50,-40,-30,-30,-30,-30,-40,-50},{-40,-20,0,0,0,0,-20,-40},
       {-30,0,10,15,15,10,0,-30},{-30,5,15,20,20,15,5,-30},
       {-30,0,15,20,20,15,0,-30},{-30,5,10,15,15,10,5,-30},
       {-40,-20,0,5,5,0,-20,-40},{-50,-40,-30,-30,-30,-30,-40,-50}},
    B={{-20,-10,-10,-10,-10,-10,-10,-20},{-10,0,0,0,0,0,0,-10},
       {-10,0,5,10,10,5,0,-10},{-10,5,5,10,10,5,5,-10},
       {-10,0,10,10,10,10,0,-10},{-10,10,10,10,10,10,10,-10},
       {-10,5,0,0,0,0,5,-10},{-20,-10,-10,-10,-10,-10,-10,-20}},
    R={{0,0,0,0,0,0,0,0},{5,10,10,10,10,10,10,5},{-5,0,0,0,0,0,0,-5},
       {-5,0,0,0,0,0,0,-5},{-5,0,0,0,0,0,0,-5},{-5,0,0,0,0,0,0,-5},
       {-5,0,0,0,0,0,0,-5},{0,0,0,5,5,0,0,0}},
    Q={{-20,-10,-10,-5,-5,-10,-10,-20},{-10,0,0,0,0,0,0,-10},
       {-10,0,5,5,5,5,0,-10},{-5,0,5,5,5,5,0,-5},{0,0,5,5,5,5,0,-5},
       {-10,5,5,5,5,5,0,-10},{-10,0,5,0,0,0,0,-10},{-20,-10,-10,-5,-5,-10,-10,-20}},
    K={{-30,-40,-40,-50,-50,-40,-40,-30},{-30,-40,-40,-50,-50,-40,-40,-30},
       {-30,-40,-40,-50,-50,-40,-40,-30},{-30,-40,-40,-50,-50,-40,-40,-30},
       {-20,-30,-30,-40,-40,-30,-30,-20},{-10,-20,-20,-20,-20,-20,-20,-10},
       {20,20,0,0,0,0,20,20},{20,30,10,0,0,10,30,20}},
}

-- ============================================================
-- GAME STATE
-- ============================================================
local function emptyBoard()
    local b={}
    for r=1,8 do b[r]={} for c=1,8 do b[r][c]=nil end end
    return b
end

local function newGameState()
    return {
        board=emptyBoard(), turn="w", myColor="w",
        opponent=nil, gameActive=false, aiMode=false,
        selR=nil, selC=nil, validMoves={},
        epTarget=nil, castling={},
        lastFrom=nil, lastTo=nil,
        inCheck=false, gameOver=false, winner=nil,
        aiPending=false,
        diff=defaultDiff,
        startTimestamp=0, elapsedSeconds=0, paused=false,
        undo={},          -- snapshot stack (for Undo vs AI)
        mate=nil,         -- cached mate distance for side to move
        rematchOffered=false,
    }
end

local games = {}
for i=1,MAX_GAMES do games[i]=newGameState() end
local activeIdx  = 1
local G          = games[activeIdx]
local openTabs   = 1     -- how many Chrome tabs are currently visible (1..MAX_GAMES)

local pendingChallenge  = nil
local outgoingChallenge = nil

-- UI references
local BoardFrame
local ChessFrame, SquareBtns, TurnLabel, OppLabel, StatusLabel, TimerLabel, MateLabel, NoticeLabel
local DiffBtns  = {}
local TabWidgets = {}
local PlusBtn = nil
local UndoBtn = nil
local ArenaCheck, EscCheck = nil, nil
local HistoryFrame = nil
local ChallengePopup = nil
local ConfirmPopup = nil

-- ============================================================
-- HELPERS
-- ============================================================
local function shortName(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

-- ============================================================
-- CHESS LOGIC
-- Motor rapido: tablas de consulta en vez de string:sub, ataques
-- detectados mirando desde la casilla (sin generar las jugadas del
-- rival) y hacer/deshacer sobre un solo tablero durante la busqueda.
-- La busqueda no crea tablas por nodo: menos basura, menos tirones del GC.
-- ============================================================
local PCOL, PTYP, PNAME = {}, {}, { w={}, b={} }
for _,cl in ipairs({"w","b"}) do
    for _,t in ipairs({"P","N","B","R","Q","K"}) do
        local p=cl..t; PCOL[p]=cl; PTYP[p]=t; PNAME[cl][t]=p
    end
end

-- leer t[nil] devuelve nil en Lua 5.1, asi que no hace falta chequear p
local function col(p) return PCOL[p] end
local function typ(p) return PTYP[p] end
local function opp(c) return c=="w" and "b" or "w" end
local function inb(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end

local function copyBoard(b)
    local n={}
    for r=1,8 do local s=b[r]; local d={}; n[r]=d; for c=1,8 do d[c]=s[c] end end
    return n
end

local KN_DR={2,2,-2,-2,1,1,-1,-1}; local KN_DC={1,-1,1,-1,2,-2,2,-2}
local KG_DR={1,1,1,0,0,-1,-1,-1};  local KG_DC={1,0,-1,1,-1,1,0,-1}
local DG_DR={1,1,-1,-1};           local DG_DC={1,-1,1,-1}
local OR_DR={1,-1,0,0};            local OR_DC={0,0,1,-1}

-- True si la casilla (r,c) esta atacada por el color 'by'.
local function attacked(b,r,c,by)
    local N=PNAME[by]
    -- un peon blanco ataca hacia arriba: se para una fila por debajo
    local pr=(by=="w") and r-1 or r+1
    if pr>=1 and pr<=8 then
        local row=b[pr]; local P=N.P
        if c>1 and row[c-1]==P then return true end
        if c<8 and row[c+1]==P then return true end
    end
    local Kn,Kg=N.N,N.K
    for i=1,8 do
        local tr,tc=r+KN_DR[i],c+KN_DC[i]
        if tr>=1 and tr<=8 and tc>=1 and tc<=8 and b[tr][tc]==Kn then return true end
    end
    for i=1,8 do
        local tr,tc=r+KG_DR[i],c+KG_DC[i]
        if tr>=1 and tr<=8 and tc>=1 and tc<=8 and b[tr][tc]==Kg then return true end
    end
    local B,R,Q=N.B,N.R,N.Q
    for i=1,4 do
        local dr,dc=DG_DR[i],DG_DC[i]; local tr,tc=r+dr,c+dc
        while tr>=1 and tr<=8 and tc>=1 and tc<=8 do
            local p=b[tr][tc]
            if p then if p==B or p==Q then return true end break end
            tr,tc=tr+dr,tc+dc
        end
    end
    for i=1,4 do
        local dr,dc=OR_DR[i],OR_DC[i]; local tr,tc=r+dr,c+dc
        while tr>=1 and tr<=8 and tc>=1 and tc<=8 do
            local p=b[tr][tc]
            if p then if p==R or p==Q then return true end break end
            tr,tc=tr+dr,tc+dc
        end
    end
    return false
end

-- ---- Enroque como mascara de bits (no crea tablas en la busqueda) ----
local CAS_WK, CAS_WQ, CAS_BK, CAS_BQ = 1,2,4,8
local function hasBit(x,f) return x%(f+f)>=f end
local function casToMask(cas)
    if not cas then return 0 end
    local m=0
    if cas.wK and cas.wRh then m=m+CAS_WK end
    if cas.wK and cas.wRa then m=m+CAS_WQ end
    if cas.bK and cas.bRh then m=m+CAS_BK end
    if cas.bK and cas.bRa then m=m+CAS_BQ end
    return m
end
-- casilla (indice 1..64) -> derechos que se pierden si algo sale o llega ahi
local CAS_NEXT={}
do
    local clear={ [5]=CAS_WK+CAS_WQ, [8]=CAS_WK, [1]=CAS_WQ,
                  [61]=CAS_BK+CAS_BQ, [64]=CAS_BK, [57]=CAS_BQ }
    for sq,bits in pairs(clear) do
        local t={}
        for x=0,15 do
            local y=x
            for _,f in ipairs({1,2,4,8}) do
                if hasBit(bits,f) and hasBit(y,f) then y=y-f end
            end
            t[x]=y
        end
        CAS_NEXT[sq]=t
    end
end
local function casAfter(cas,m)
    if cas==0 then return 0 end
    local t=CAS_NEXT[(m.fr-1)*8+m.fc]; if t then cas=t[cas] end
    t=CAS_NEXT[(m.tr-1)*8+m.tc]; if t then cas=t[cas] end
    return cas
end
-- al paso como indice de casilla (0 = ninguno)
local function epAfter(m)
    if m.sp=="dp" then return ((m.fr+m.tr)/2-1)*8+m.fc end
    return 0
end
local function epToSq(ep)
    if ep and ep[1] and ep[2] then return (ep[1]-1)*8+ep[2] end
    return 0
end

-- ---- Generacion de jugadas sobre un buffer reutilizable ----
local function addMove(list,n,fr,fc,tr,tc,sp,promo)
    n=n+1
    local m=list[n]
    if not m then m={}; list[n]=m end
    m.fr=fr; m.fc=fc; m.tr=tr; m.tc=tc; m.sp=sp; m.promo=promo; m.score=0
    return n
end

local function slideGen(b,list,n,r,c,cl,DR,DC,capsOnly)
    for i=1,4 do
        local dr,dc=DR[i],DC[i]; local tr,tc=r+dr,c+dc
        while tr>=1 and tr<=8 and tc>=1 and tc<=8 do
            local t=b[tr][tc]
            if t then
                if PCOL[t]~=cl then n=addMove(list,n,r,c,tr,tc) end
                break
            end
            if not capsOnly then n=addMove(list,n,r,c,tr,tc) end
            tr,tc=tr+dr,tc+dc
        end
    end
    return n
end

-- Jugadas pseudo-legales de 'cl'. capsOnly = solo capturas y coronaciones.
-- La coronacion se genera a dama; la eleccion del jugador se aplica aparte.
local function genPseudo(b,cl,epSq,cas,list,capsOnly)
    local n=0
    local N=PNAME[cl]; local Q=N.Q
    local d=(cl=="w") and 1 or -1
    local startR=(cl=="w") and 2 or 7
    local lastR=(cl=="w") and 8 or 1
    for r=1,8 do
        local row=b[r]
        for c=1,8 do
            local p=row[c]
            if p and PCOL[p]==cl then
                local t=PTYP[p]
                if t=="P" then
                    local tr=r+d
                    if tr>=1 and tr<=8 then
                        if not b[tr][c] then
                            if tr==lastR then n=addMove(list,n,r,c,tr,c,nil,Q)
                            elseif not capsOnly then
                                n=addMove(list,n,r,c,tr,c)
                                if r==startR and not b[tr+d][c] then n=addMove(list,n,r,c,tr+d,c,"dp") end
                            end
                        end
                        for dc=-1,1,2 do
                            local tc=c+dc
                            if tc>=1 and tc<=8 then
                                local t2=b[tr][tc]
                                if t2 then
                                    if PCOL[t2]~=cl then n=addMove(list,n,r,c,tr,tc,nil,(tr==lastR) and Q or nil) end
                                elseif epSq==(tr-1)*8+tc then
                                    n=addMove(list,n,r,c,tr,tc,"ep")
                                end
                            end
                        end
                    end
                elseif t=="N" or t=="K" then
                    local DR,DC=KN_DR,KN_DC
                    if t=="K" then DR,DC=KG_DR,KG_DC end
                    for i=1,8 do
                        local tr,tc=r+DR[i],c+DC[i]
                        if tr>=1 and tr<=8 and tc>=1 and tc<=8 then
                            local t2=b[tr][tc]
                            if t2 then
                                if PCOL[t2]~=cl then n=addMove(list,n,r,c,tr,tc) end
                            elseif not capsOnly then n=addMove(list,n,r,c,tr,tc) end
                        end
                    end
                    if t=="K" and not capsOnly and cas>0 then
                        local br=(cl=="w") and 1 or 8
                        if r==br and c==5 then
                            local kf=(cl=="w") and CAS_WK or CAS_BK
                            local qf=kf+kf
                            local R=N.R; local oc=opp(cl)
                            -- el rey no puede estar en jaque ni cruzar casillas atacadas;
                            -- la casilla final la valida genLegal como cualquier jugada
                            if hasBit(cas,kf) and row[8]==R and not row[6] and not row[7]
                               and not attacked(b,br,5,oc) and not attacked(b,br,6,oc) then
                                n=addMove(list,n,r,c,br,7,"cK")
                            end
                            if hasBit(cas,qf) and row[1]==R and not row[2] and not row[3] and not row[4]
                               and not attacked(b,br,5,oc) and not attacked(b,br,4,oc) then
                                n=addMove(list,n,r,c,br,3,"cQ")
                            end
                        end
                    end
                elseif t=="B" then n=slideGen(b,list,n,r,c,cl,DG_DR,DG_DC,capsOnly)
                elseif t=="R" then n=slideGen(b,list,n,r,c,cl,OR_DR,OR_DC,capsOnly)
                elseif t=="Q" then
                    n=slideGen(b,list,n,r,c,cl,DG_DR,DG_DC,capsOnly)
                    n=slideGen(b,list,n,r,c,cl,OR_DR,OR_DC,capsOnly)
                end
            end
        end
    end
    return n
end

-- ---- Contexto de busqueda: tablero propio + reyes + buffers por ply ----
-- Cada busqueda (IA, mate en N) tiene su contexto, asi una corrutina
-- suspendida nunca pisa el estado de otra.
local function findKing(board,color)
    local K=PNAME[color].K
    for r=1,8 do local row=board[r]; for c=1,8 do
        if row[c]==K then return r,c end end end
    return nil,nil
end

local function bindCtx(ctx,board)
    ctx.b=board
    ctx.kr.w,ctx.kc.w=findKing(board,"w")
    ctx.kr.b,ctx.kc.b=findKing(board,"b")
    return ctx
end
local function newCtx(board)
    return bindCtx({ kr={}, kc={}, bufs={}, nodes=0 }, copyBoard(board))
end
local function getBuf(ctx,ply)
    local l=ctx.bufs[ply]
    if not l then l={}; ctx.bufs[ply]=l end
    return l
end

local function makeMove(ctx,m)
    local b=ctx.b
    local fr,fc,tr,tc,sp=m.fr,m.fc,m.tr,m.tc,m.sp
    local piece=b[fr][fc]; local cap
    if sp=="ep" then cap=b[fr][tc]; b[fr][tc]=nil else cap=b[tr][tc] end
    local placed=m.promo
    if not placed and PTYP[piece]=="P" and (tr==8 or tr==1) then placed=PNAME[PCOL[piece]].Q end
    b[tr][tc]=placed or piece; b[fr][fc]=nil
    if sp=="cK" then b[tr][6]=b[tr][8]; b[tr][8]=nil
    elseif sp=="cQ" then b[tr][4]=b[tr][1]; b[tr][1]=nil end
    if PTYP[piece]=="K" then local cl=PCOL[piece]; ctx.kr[cl]=tr; ctx.kc[cl]=tc end
    return piece,cap
end

local function unmakeMove(ctx,m,piece,cap)
    local b=ctx.b
    local fr,fc,tr,tc,sp=m.fr,m.fc,m.tr,m.tc,m.sp
    b[fr][fc]=piece
    if sp=="ep" then b[tr][tc]=nil; b[fr][tc]=cap
    else
        b[tr][tc]=cap
        if sp=="cK" then b[tr][8]=b[tr][6]; b[tr][6]=nil
        elseif sp=="cQ" then b[tr][1]=b[tr][4]; b[tr][4]=nil end
    end
    if PTYP[piece]=="K" then local cl=PCOL[piece]; ctx.kr[cl]=fr; ctx.kc[cl]=fc end
end

local function ctxInCheck(ctx,cl)
    local r=ctx.kr[cl]
    if not r then return true end   -- sin rey (tablero roto): tratar como jaque
    return attacked(ctx.b,r,ctx.kc[cl],opp(cl))
end

-- Deja en list[1..k] solo las jugadas legales (compacta en el lugar).
local function genLegal(ctx,cl,epSq,cas,list,capsOnly)
    if not ctx.kr[cl] then return 0 end
    local b=ctx.b
    local n=genPseudo(b,cl,epSq,cas,list,capsOnly)
    local oc=opp(cl); local kr,kc=ctx.kr,ctx.kc
    local k=0
    for i=1,n do
        local m=list[i]
        local piece,cap=makeMove(ctx,m)
        local ok=not attacked(b,kr[cl],kc[cl],oc)
        unmakeMove(ctx,m,piece,cap)
        if ok then
            k=k+1
            if k~=i then list[i],list[k]=list[k],list[i] end
        end
    end
    return k
end

local function copyMove(m)
    if not m then return nil end
    return { fr=m.fr, fc=m.fc, tr=m.tr, tc=m.tc, sp=m.sp, promo=m.promo }
end

-- ---- API "de tablero" para la UI (sincronica, nunca cede) ----
local UICTX={ kr={}, kc={}, bufs={} }

local function isInCheck(board,color)
    local kr,kc=findKing(board,color)
    if not kr then return true end
    return attacked(board,kr,kc,opp(color))
end

local function allLegalMoves(board,color,ep,cas)
    local ctx=bindCtx(UICTX,board)
    local list=getBuf(ctx,1)
    local n=genLegal(ctx,color,epToSq(ep),casToMask(cas),list,false)
    local out={}
    for i=1,n do out[i]=copyMove(list[i]) end
    return out
end

local function legalMoves(board,r,c,ep,cas)
    local piece=board[r][c]; if not piece then return {} end
    local out={}
    for _,m in ipairs(allLegalMoves(board,PCOL[piece],ep,cas)) do
        if m.fr==r and m.fc==c then out[#out+1]=m end
    end
    return out
end

local function hasLegalMoves(board,color,ep,cas)
    local ctx=bindCtx(UICTX,board)
    return genLegal(ctx,color,epToSq(ep),casToMask(cas),getBuf(ctx,1),false)>0
end

local function applyMove(board,mv)
    local nb=copyBoard(board); local piece=nb[mv.fr][mv.fc]
    nb[mv.tr][mv.tc]=piece; nb[mv.fr][mv.fc]=nil
    if mv.sp=="ep" then nb[mv.fr][mv.tc]=nil   -- el peon capturado queda al lado del origen
    elseif mv.sp=="cK" then nb[mv.tr][6]=nb[mv.tr][8]; nb[mv.tr][8]=nil
    elseif mv.sp=="cQ" then nb[mv.tr][4]=nb[mv.tr][1]; nb[mv.tr][1]=nil end
    if PTYP[piece]=="P" and (mv.tr==8 or mv.tr==1) then
        local cl=PCOL[piece]
        local pr=mv.promo
        if not (pr and PCOL[pr]==cl and PTYP[pr]~="P" and PTYP[pr]~="K") then pr=PNAME[cl].Q end
        nb[mv.tr][mv.tc]=pr
    end
    return nb
end

local function countPieces(board)
    local n=0
    for r=1,8 do local row=board[r]; for c=1,8 do if row[c] then n=n+1 end end end
    return n
end

-- Material insuficiente: K-K, K+menor vs K, o solo alfiles del mismo color de casilla.
local function insufficientMaterial(board)
    local minors, bishopsOnly, sqColor = 0, true, nil
    local sameColor=true
    for r=1,8 do for c=1,8 do
        local p=board[r][c]
        if p then
            local t=PTYP[p]
            if t=="P" or t=="R" or t=="Q" then return false end
            if t=="N" or t=="B" then
                minors=minors+1
                if t=="N" then bishopsOnly=false
                else
                    local sc=(r+c)%2
                    if sqColor==nil then sqColor=sc elseif sqColor~=sc then sameColor=false end
                end
            end
        end
    end end
    if minors<=1 then return true end
    return bishopsOnly and sameColor
end

-- ---- Clave de posicion (repeticion) ----
-- El al paso solo cuenta si el bando que mueve tiene un peon que podria tomarlo.
local function epRelevant(b,turn,epSq)
    if not epSq or epSq==0 then return false end
    local er=math.floor((epSq-1)/8)+1; local ec=(epSq-1)%8+1
    local pr=(turn=="w") and er-1 or er+1
    if pr<1 or pr>8 then return false end
    local P=PNAME[turn].P
    return (ec>1 and b[pr][ec-1]==P) or (ec<8 and b[pr][ec+1]==P) or false
end
local KEYBUF={}
local function positionKey(b,turn,casMask,epSq)
    local i=0
    for r=1,8 do local row=b[r]; for c=1,8 do i=i+1; KEYBUF[i]=row[c] or "." end end
    KEYBUF[65]=turn; KEYBUF[66]=casMask; KEYBUF[67]=":"
    KEYBUF[68]=epRelevant(b,turn,epSq) and epSq or 0
    return table.concat(KEYBUF,"",1,68)
end
local function gameKey(g)
    return positionKey(g.board,g.turn,casToMask(g.castling),epToSq(g.epTarget))
end

-- ============================================================
-- EVALUATION
-- ============================================================
-- Material + tabla de posicion precalculados por pieza y casilla (con signo:
-- blancas suman, negras restan). Evaluar = 64 lecturas, sin llamadas.
local PSQ={}
for _,cl in ipairs({"w","b"}) do
    for _,t in ipairs({"P","N","B","R","Q","K"}) do
        local sign=(cl=="w") and 1 or -1
        local tbl=PST[t]; local s={}
        for r=1,8 do
            s[r]={}
            local pr=(cl=="w") and (9-r) or r
            for c=1,8 do s[r][c]=sign*(PVAL[t]+((tbl and tbl[pr] and tbl[pr][c]) or 0)) end
        end
        PSQ[cl..t]=s
    end
end

local function evalBoard(board)
    local score=0
    for r=1,8 do
        local row=board[r]
        for c=1,8 do
            local p=row[c]
            if p then score=score+PSQ[p][r][c] end
        end
    end
    return score
end

-- ---- Busqueda cooperativa (no bloquea el juego) --------------
-- Toda la busqueda corre en una corrutina. Cada pocos nodos se mira el reloj
-- y, si ya se gasto el presupuesto de este frame, se cede (yield) para que
-- WoW dibuje. El presupuesto se ajusta a los FPS (ver aiTimer).
local profclock = debugprofilestop or function() return GetTime()*1000 end
local SEARCH = { nodes=0, sliceStart=0, budget=6 }
local function ytick()
    local n=SEARCH.nodes+1
    if n>=4 then
        n=0
        if (profclock()-SEARCH.sliceStart)>SEARCH.budget and coroutine.running() then
            coroutine.yield()
            SEARCH.sliceStart=profclock()
        end
    end
    SEARCH.nodes=n
end

-- Orden de jugadas: capturas por MVV-LVA (victima grande, atacante chico)
-- y coronaciones primero -> muchos mas cortes alfa-beta.
local LVA={ P=1, N=3, B=3, R=5, Q=9, K=10 }
local function scoreMoves(b,list,n)
    for i=1,n do
        local m=list[i]; local s=0
        local v=b[m.tr][m.tc]
        if v then s=1000+PVAL[PTYP[v]]-LVA[PTYP[b[m.fr][m.fc]]]
        elseif m.sp=="ep" then s=1000+PVAL.P-LVA.P end
        if m.promo then s=s+2000 end
        m.score=s
    end
end
-- Seleccion perezosa: trae al frente la mejor que queda (si hay corte, no se ordena el resto).
local function pickBest(list,i,n)
    local bi,bs=i,list[i].score
    for j=i+1,n do
        local s=list[j].score
        if s>bs then bi,bs=j,s end
    end
    if bi~=i then list[i],list[bi]=list[bi],list[i] end
end

local INF=math.huge
local MATE=90000

-- Quiescence: en el horizonte sigue resolviendo capturas (y salidas de jaque)
-- hasta que la posicion quede tranquila. Evita que la IA cuelgue piezas.
local function qsearch(ctx,ply,alpha,beta,cl,epSq,cas,qd)
    ytick()
    local b=ctx.b
    local inChk=ctxInCheck(ctx,cl)
    if not inChk then
        local stand=evalBoard(b); if cl=="b" then stand=-stand end
        if stand>=beta then return beta end
        if stand>alpha then alpha=stand end
        if qd<=0 then return alpha end
    elseif qd<=0 then
        local s=evalBoard(b); return (cl=="w") and s or -s
    end
    local list=getBuf(ctx,ply)
    local n=genLegal(ctx,cl,epSq,cas,list,not inChk)
    if n==0 then
        if inChk then return -MATE end
        return alpha
    end
    scoreMoves(b,list,n)
    local oc=opp(cl)
    for i=1,n do
        pickBest(list,i,n)
        local m=list[i]
        local piece,cap=makeMove(ctx,m)
        local sc=-qsearch(ctx,ply+1,-beta,-alpha,oc,epAfter(m),casAfter(cas,m),qd-1)
        unmakeMove(ctx,m,piece,cap)
        if sc>=beta then return beta end
        if sc>alpha then alpha=sc end
    end
    return alpha
end

-- Negamax alfa-beta: el puntaje es siempre desde el bando que mueve.
local function negamax(ctx,ply,depth,alpha,beta,cl,epSq,cas,useQS)
    ytick()
    if depth<=0 then
        if useQS then return qsearch(ctx,ply,alpha,beta,cl,epSq,cas,4) end
        local s=evalBoard(ctx.b); return (cl=="w") and s or -s
    end
    local b=ctx.b
    local list=getBuf(ctx,ply)
    local n=genLegal(ctx,cl,epSq,cas,list,false)
    if n==0 then
        -- mate mas cercano a la raiz = peor para el que lo sufre
        if ctxInCheck(ctx,cl) then return -(MATE+depth) end
        return 0
    end
    scoreMoves(b,list,n)
    local oc=opp(cl)
    local best=-INF
    for i=1,n do
        pickBest(list,i,n)
        local m=list[i]
        local piece,cap=makeMove(ctx,m)
        local sc=-negamax(ctx,ply+1,depth-1,-beta,-alpha,oc,epAfter(m),casAfter(cas,m),useQS)
        unmakeMove(ctx,m,piece,cap)
        if sc>best then best=sc end
        if sc>alpha then alpha=sc end
        if alpha>=beta then break end
    end
    return best
end

-- Raiz: ademas evita (o busca, si va perdiendo) tablas por repeticion y 50 jugadas.
local function rootSearch(ctx,depth,cl,epSq,cas,useQS,reps,halfmove)
    local b=ctx.b
    local list=getBuf(ctx,1)
    local n=genLegal(ctx,cl,epSq,cas,list,false)
    if n==0 then return nil end
    scoreMoves(b,list,n)
    local oc=opp(cl)
    local alpha,beta=-INF,INF
    local best,bestM=-INF,nil
    for i=1,n do
        pickBest(list,i,n)
        local m=list[i]
        local resets=(PTYP[b[m.fr][m.fc]]=="P") or b[m.tr][m.tc] or m.sp=="ep"
        local piece,cap=makeMove(ctx,m)
        local nep,ncas=epAfter(m),casAfter(cas,m)
        local sc
        if reps and (reps[positionKey(b,oc,ncas,nep)] or 0)>=2 then
            sc=0
        else
            sc=-negamax(ctx,2,depth-1,-beta,-alpha,oc,nep,ncas,useQS)
            -- la jugada 100 sin captura ni peon es tablas, salvo que de mate
            if (not resets) and halfmove and halfmove+1>=100 and sc<MATE then sc=0 end
        end
        unmakeMove(ctx,m,piece,cap)
        if sc>best then best=sc; bestM=m end
        if sc>alpha then alpha=sc end
    end
    return copyMove(bestM)
end

-- ============================================================
-- MATE-IN-N SOLVER (indicador "mate en N"; corre en corrutina)
-- ============================================================
local MATE_NODE_LIMIT=250000   -- si se pasa, se abandona (indicador vacio)

-- True si 'cl' (que mueve) fuerza mate en n jugadas o menos.
local function forceMate(ctx,ply,cl,n,epSq,cas)
    ytick()
    ctx.nodes=ctx.nodes+1
    if ctx.nodes>MATE_NODE_LIMIT then ctx.abort=true end
    if ctx.abort then return false end
    local list=getBuf(ctx,ply)
    local cnt=genLegal(ctx,cl,epSq,cas,list,false)
    local oc=opp(cl)
    for i=1,cnt do
        local m=list[i]
        local piece,cap=makeMove(ctx,m)
        local nep,ncas=epAfter(m),casAfter(cas,m)
        local replies=getBuf(ctx,ply+1)
        local rc=genLegal(ctx,oc,nep,ncas,replies,false)
        local ok=false
        if rc==0 then
            ok=ctxInCheck(ctx,oc)   -- sin respuestas: mate si hay jaque, ahogado si no
        elseif n>1 then
            ok=true
            for j=1,rc do
                local rm=replies[j]
                local p2,c2=makeMove(ctx,rm)
                local sub=forceMate(ctx,ply+2,cl,n-1,epAfter(rm),casAfter(ncas,rm))
                unmakeMove(ctx,rm,p2,c2)
                if not sub then ok=false; break end
            end
        end
        unmakeMove(ctx,m,piece,cap)
        if ok then return true end
        if ctx.abort then return false end
    end
    return false
end

-- Distancia de mate para el bando que mueve; profundidad segun material.
local function mateDistance(ctx,side,epSq,cas)
    local pc=countPieces(ctx.b)
    local maxN=(pc<=6 and 3) or (pc<=12 and 2) or 1
    for n=1,maxN do
        if forceMate(ctx,1,side,n,epSq,cas) then return n end
        if ctx.abort then return nil end
    end
    return nil
end

local function getAIMove(g)
    g = g or G
    local aiColor=opp(g.myColor)
    local diff=DIFFICULTIES[g.diff] or DIFFICULTIES[3]
    local moves=allLegalMoves(g.board,aiColor,g.epTarget,g.castling)
    if #moves==0 then return nil end
    if diff.mode=="random" then return moves[math.random(#moves)] end
    if diff.mode=="greedy" then
        local best=nil; local bestVal=-1
        for _,m in ipairs(moves) do
            local t=g.board[m.tr][m.tc]; local v=t and (PVAL[typ(t)] or 0) or 0
            if v>bestVal then bestVal=v; best=m end
        end
        return (bestVal>0) and best or moves[math.random(#moves)]
    end
    if diff.mode=="eval" then
        local all={}
        for _,m in ipairs(moves) do
            local nb=applyMove(g.board,m)
            local score=evalBoard(nb)*(aiColor=="b" and -1 or 1)+math.random()*15
            table.insert(all,{m=m,s=score})
        end
        table.sort(all,function(a,b) return a.s>b.s end)
        return all[math.random(math.min(2,#all))].m
    end
    if diff.mode=="minimax" then
        -- se busca sobre una copia: la corrutina cede a mitad de arbol y el
        -- tablero de la partida no puede quedar a medio mover en pantalla
        local ctx=newCtx(g.board)
        local mv=rootSearch(ctx,diff.depth,aiColor,epToSq(g.epTarget),casToMask(g.castling),
                            diff.qsearch,g.reps,g.halfmove or 0)
        return mv or moves[math.random(#moves)]
    end
    return moves[math.random(#moves)]
end

-- ============================================================
-- TIME
-- ============================================================
local function formatSeconds(s)
    s=math.floor(s or 0)
    local h=math.floor(s/3600)
    local m=math.floor((s%3600)/60)
    local sec=s%60
    if h>0 then return format("%d:%02d:%02d",h,m,sec)
    else         return format("%d:%02d",m,sec) end
end

local function gElapsed(g)
    g = g or G
    if g.startTimestamp>0 and g.gameActive and not g.gameOver then
        return time()-g.startTimestamp+(g.elapsedSeconds or 0)
    end
    return g.elapsedSeconds or 0
end

local function pauseGame(g)
    if not g then return end
    if g.gameActive and not g.gameOver and g.startTimestamp>0 then
        g.elapsedSeconds = time()-g.startTimestamp+(g.elapsedSeconds or 0)
    end
    g.startTimestamp = 0; g.paused = true
end

local function resumeGame(g)
    if not g then return end
    if g.gameActive and not g.gameOver then g.startTimestamp = time() end
    g.paused = false
end

-- ============================================================
-- BOARD INITIALIZATION (acts on active game G)
-- ============================================================
local function initBoard()
    G.board=emptyBoard()
    local back={"R","N","B","Q","K","B","N","R"}
    for c=1,8 do
        G.board[8][c]="b"..back[c]; G.board[7][c]="bP"
        G.board[2][c]="wP";         G.board[1][c]="w"..back[c]
    end
    G.turn="w"; G.selR=nil; G.selC=nil; G.validMoves={}
    G.epTarget=nil
    G.castling={wK=true,wRa=true,wRh=true,bK=true,bRa=true,bRh=true}
    G.lastFrom=nil; G.lastTo=nil; G.inCheck=false; G.gameOver=false; G.winner=nil
    G.startTimestamp=time(); G.elapsedSeconds=0; G.paused=false
    G.undo={}; G.mate=nil; G.mateJob=nil; G.rematchOffered=false; G.thinker=nil
    -- regla de 50 jugadas y triple repeticion
    G.halfmove=0; G.drawReason=nil
    G.posKey=gameKey(G); G.reps={ [G.posKey]=1 }
end

-- ============================================================
-- HISTORY
-- ============================================================
local function getResultForPlayer(g,winner)
    if winner=="draw" then return "draw" end
    if winner==g.myColor then return "win" end
    return "loss"
end

local function saveToHistory(g,result)
    if not DB then return end
    local diff=DIFFICULTIES[g.diff] or DIFFICULTIES[3]
    local d=date("*t")
    local entry={
        opponent  = g.aiMode and format(L["HIST_AI_OPP"],diff.name) or (shortName(g.opponent) or "?"),
        result    = result,
        myColor   = g.myColor,
        duration  = gElapsed(g),
        dateStr   = format("%02d/%02d/%04d",d.day,d.month,d.year),
        mode      = g.aiMode and "ai" or "pvp",
        diffName  = g.aiMode and diff.name or nil,
        diffColor = g.aiMode and diff.color or nil,
    }
    table.insert(DB.history,1,entry)
    while #DB.history>100 do table.remove(DB.history) end
end

-- ============================================================
-- SAVE / LOAD GAMES
-- ============================================================
local function copyReps(t)
    local n={}
    if t then for k,v in pairs(t) do n[k]=v end end
    return n
end

local function serializeGame(g)
    return {
        board     = copyBoard(g.board),
        turn      = g.turn, myColor = g.myColor, opponent = g.opponent,
        castling  = {wK=g.castling.wK,wRa=g.castling.wRa,wRh=g.castling.wRh,
                     bK=g.castling.bK,bRa=g.castling.bRa,bRh=g.castling.bRh},
        epTarget  = g.epTarget, lastFrom = g.lastFrom, lastTo = g.lastTo,
        inCheck   = g.inCheck, aiMode = g.aiMode, diff = g.diff,
        elapsed   = gElapsed(g),
        halfmove  = g.halfmove, posKey = g.posKey, reps = copyReps(g.reps),
    }
end

local function saveAllGames()
    if not DB then return end
    DB.games = {}
    for i=1,MAX_GAMES do
        local g=games[i]
        -- only persist games that live in a currently open tab
        if i<=openTabs and g and g.gameActive and not g.gameOver then
            DB.games[i]=serializeGame(g)
        end
    end
    DB.activeIdx = activeIdx
    DB.openTabs  = openTabs
end

local function deserializeInto(g,s,makeActive)
    g.board      = copyBoard(s.board)
    g.turn       = s.turn; g.myColor = s.myColor; g.opponent = s.opponent
    g.castling   = s.castling or {wK=true,wRa=true,wRh=true,bK=true,bRa=true,bRh=true}
    g.epTarget   = s.epTarget; g.lastFrom = s.lastFrom; g.lastTo = s.lastTo
    g.inCheck    = s.inCheck or false
    g.aiMode     = s.aiMode; g.diff = s.diff or 3
    g.gameActive = true; g.gameOver = false; g.winner = nil
    g.selR=nil; g.selC=nil; g.validMoves={}
    g.elapsedSeconds = s.elapsed or 0
    g.undo={}; g.mate=nil; g.mateJob=nil; g.rematchOffered=false; g.thinker=nil
    -- partidas guardadas por versiones viejas no traen estos campos
    g.halfmove   = s.halfmove or 0; g.drawReason=nil
    g.posKey     = gameKey(g)
    g.reps       = copyReps(s.reps)
    if not g.reps[g.posKey] then g.reps[g.posKey]=1 end
    g.aiPending  = (g.aiMode and g.turn~=g.myColor) or false
    if makeActive then g.startTimestamp=time(); g.paused=false
    else g.startTimestamp=0; g.paused=true end
end

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
local noticeExpire = 0
local function notify(text)
    if NoticeLabel then
        NoticeLabel:SetText("|cFFFFE080"..(text or "").."|r")
        noticeExpire = time()+7
    end
end

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================
local updateBoard, updateTabs, updateDiffButtons, clearBoardDisplay, updateMate, updateSidePanel
local showRematchPopup
local showPromotion, hidePromotion, isPromotionOpen

-- ============================================================
-- UNDO (vs AI)
-- ============================================================
local function pushUndo(g)
    g.undo = g.undo or {}
    table.insert(g.undo, {
        board=copyBoard(g.board), turn=g.turn,
        castling={wK=g.castling.wK,wRa=g.castling.wRa,wRh=g.castling.wRh,
                  bK=g.castling.bK,bRa=g.castling.bRa,bRh=g.castling.bRh},
        epTarget=g.epTarget, lastFrom=g.lastFrom, lastTo=g.lastTo,
        inCheck=g.inCheck, halfmove=g.halfmove, posKey=g.posKey,
    })
    while #g.undo>60 do table.remove(g.undo,1) end
end

-- ============================================================
-- EXECUTE MOVE
-- ============================================================
local function executeMove(mv,g)
    g = g or G
    local piece=g.board[mv.fr][mv.fc]
    if not piece then return end
    pushUndo(g)
    if typ(piece)=="K" then
        local cl=col(piece)
        g.castling[cl.."K"]=false; g.castling[cl.."Ra"]=false; g.castling[cl.."Rh"]=false
    elseif typ(piece)=="R" then
        -- solo la torre que sale de su casilla inicial pierde el enroque
        local cl=col(piece)
        if mv.fr==(cl=="w" and 1 or 8) then
            if mv.fc==1 then g.castling[cl.."Ra"]=false end
            if mv.fc==8 then g.castling[cl.."Rh"]=false end
        end
    end
    local captured=g.board[mv.tr][mv.tc]
    local resetsClock=(typ(piece)=="P") or captured or mv.sp=="ep"
    if captured and typ(captured)=="R" then
        local ccl=col(captured)
        if mv.tr==(ccl=="w" and 1 or 8) then
            if mv.tc==1 then g.castling[ccl.."Ra"]=false end
            if mv.tc==8 then g.castling[ccl.."Rh"]=false end
        end
    end
    g.lastFrom={mv.fr,mv.fc}; g.lastTo={mv.tr,mv.tc}
    g.epTarget=nil
    if mv.sp=="dp" then local d=col(piece)=="w" and -1 or 1; g.epTarget={mv.tr+d,mv.tc} end
    g.board=applyMove(g.board,mv); g.turn=opp(g.turn)
    g.halfmove=resetsClock and 0 or (g.halfmove or 0)+1
    g.posKey=gameKey(g)
    g.reps=g.reps or {}
    g.reps[g.posKey]=(g.reps[g.posKey] or 0)+1
    g.inCheck=isInCheck(g.board,g.turn)
    g.drawReason=nil
    -- el mate tiene prioridad; despues las tablas automaticas
    if not hasLegalMoves(g.board,g.turn,g.epTarget,g.castling) then
        g.gameOver=true; g.winner=g.inCheck and opp(g.turn) or "draw"
        if not g.inCheck then g.drawReason="stalemate" end
    elseif g.reps[g.posKey]>=3 then
        g.gameOver=true; g.winner="draw"; g.drawReason="repetition"
    elseif g.halfmove>=100 then
        g.gameOver=true; g.winner="draw"; g.drawReason="fifty"
    elseif insufficientMaterial(g.board) then
        g.gameOver=true; g.winner="draw"; g.drawReason="material"
    end
    g.selR=nil; g.selC=nil; g.validMoves={}
    g.mate=nil; g.mateJob=nil  -- lo recalcula updateMate (en segundo plano)
    if g.gameOver then
        saveToHistory(g,getResultForPlayer(g,g.winner))
    end
    saveAllGames()
end

-- ============================================================
-- COORDINATES
-- ============================================================
local function dispToBoard(dr,dc)
    if G.myColor=="w" then return 9-dr,dc else return dr,9-dc end
end

-- ============================================================
-- SLOT / TAB MANAGEMENT
-- ============================================================
local function countActiveGames()
    local n=0
    for i=1,MAX_GAMES do
        local g=games[i]
        if g and g.gameActive and not g.gameOver then n=n+1 end
    end
    return n
end

-- Prefer the current tab if it's free, then any other free open tab,
-- and finally open a brand new tab if we still have room.
local function pickSlotForNew()
    local cur=games[activeIdx]
    if not (cur and cur.gameActive and not cur.gameOver) then return activeIdx end
    for i=1,openTabs do
        local g=games[i]
        if not (g and g.gameActive and not g.gameOver) then return i end
    end
    if openTabs<MAX_GAMES then
        openTabs=openTabs+1
        if not games[openTabs] then games[openTabs]=newGameState() end
        return openTabs
    end
    return activeIdx
end

local function setActiveSlot(idx)
    if idx==activeIdx then return end
    hidePromotion()
    pauseGame(games[activeIdx])
    activeIdx=idx
    if not games[idx] then games[idx]=newGameState() end
    if openTabs<idx then openTabs=idx end
    G=games[idx]
    resumeGame(G)
end

local function switchToTab(idx)
    if idx<1 or idx>MAX_GAMES then return end
    if idx>openTabs then return end
    if idx==activeIdx then return end
    setActiveSlot(idx)
    updateDiffButtons(); updateTabs(); updateSidePanel(); updateBoard()
end
API.SwitchTab = switchToTab

local function openNewTab()
    if openTabs>=MAX_GAMES then return end
    openTabs=openTabs+1
    if not games[openTabs] then games[openTabs]=newGameState() end
    setActiveSlot(openTabs)
    updateDiffButtons(); updateTabs(); updateSidePanel(); clearBoardDisplay()
    saveAllGames()
end

local function closeTab(idx)
    if openTabs<=1 then return end          -- always keep at least one tab
    if idx<1 or idx>openTabs then return end
    hidePromotion()
    local g=games[idx]
    if g and g.gameActive and not g.gameOver then
        -- abandon the game living in that tab
        if not g.aiMode and g.opponent then
            SendAddonMessage(PREFIX,"RESIGN","WHISPER",g.opponent)
        end
        saveToHistory(g,"loss")
    end
    -- shift the remaining tabs left so there are no gaps
    for i=idx,openTabs-1 do games[i]=games[i+1] end
    games[openTabs]=newGameState()
    openTabs=openTabs-1
    if activeIdx==idx then activeIdx=math.min(idx,openTabs)
    elseif activeIdx>idx then activeIdx=activeIdx-1 end
    if activeIdx<1 then activeIdx=1 end
    G=games[activeIdx]; resumeGame(G)
    updateDiffButtons(); updateTabs(); updateSidePanel()
    if G.gameActive then updateBoard() else clearBoardDisplay() end
    saveAllGames()
end

-- ============================================================
-- DIFFICULTY BUTTONS
-- ============================================================
updateDiffButtons = function()
    local hd = (G.aiMode and G.gameActive and not G.gameOver) and G.diff or defaultDiff
    for i,btn in ipairs(DiffBtns) do
        if i==hd then
            btn:SetText("|cFF"..DIFFICULTIES[i].color..">> "..DIFFICULTIES[i].name.."|r")
        else
            btn:SetText("|cFFAAAAAA"..DIFFICULTIES[i].name.."|r")
        end
    end
end

-- ============================================================
-- TABS (Chrome style)
-- ============================================================
local function tabLabel(g)
    if not (g and g.gameActive) then return L["TAB_EMPTY"] end
    if g.aiMode then return L["TAB_VS_AI"] end
    return shortName(g.opponent) or L["HIST_PVP"]
end

updateTabs = function()
    if not TabWidgets[1] then return end
    local strip  = TabWidgets[1].frame:GetParent()
    local stripW = SQ*8
    local gap    = 3
    -- reserve room for the "+" button while more tabs can still be opened
    local plusW  = (openTabs<MAX_GAMES) and (TAB_H+gap) or 0
    local tabW   = math.floor((stripW - plusW - (openTabs-1)*gap)/openTabs)
    if tabW>108 then tabW=108 end
    if tabW<44  then tabW=44  end
    -- rough character budget so long names don't wrap onto a second line
    local maxChars = math.max(3, math.floor((tabW-24)/7))

    local x0=0
    for i=1,MAX_GAMES do
        local w=TabWidgets[i]
        if i<=openTabs then
            local g=games[i]
            local lbl=tabLabel(g)
            if g and g.gameActive and g.gameOver then lbl=lbl.." *" end
            if string.len(lbl)>maxChars then lbl=string.sub(lbl,1,maxChars) end
            w.frame:Show()
            w.frame:SetSize(tabW,TAB_H)
            w.frame:ClearAllPoints()
            w.frame:SetPoint("TOPLEFT", strip, "TOPLEFT", x0, 0)
            w.text:SetWidth(tabW-22)
            if i==activeIdx then
                w.bg:SetTexture(0.85,0.65,0.15,0.95)
                w.text:SetText("|cFF201509"..lbl.."|r")
            else
                w.bg:SetTexture(0.22,0.18,0.11,0.9)
                w.text:SetText("|cFFDDCCAA"..lbl.."|r")
            end
            -- a tab can be closed as long as it isn't the last one
            if openTabs>1 then w.close:Show() else w.close:Hide() end
            x0 = x0 + tabW + gap
        else
            w.frame:Hide()
        end
    end
    if PlusBtn then
        if openTabs<MAX_GAMES then
            PlusBtn:ClearAllPoints()
            PlusBtn:SetPoint("TOPLEFT", strip, "TOPLEFT", x0, 0)
            PlusBtn:Show()
        else
            PlusBtn:Hide()
        end
    end
end

-- ============================================================
-- MATE INDICATOR
-- ============================================================
updateMate = function()
    if not MateLabel then return end
    if not (G.gameActive and not G.gameOver) then MateLabel:SetText(""); return end
    -- Only look for forced mate in endgames (cheap + where it actually matters).
    -- In the opening/midgame it's both costly and almost never forced.
    if countPieces(G.board) > 10 then MateLabel:SetText(""); G.mate=0; return end
    if G.mate==nil then
        -- antes esto corria entero aca y congelaba el juego; ahora se arma una
        -- corrutina que aiTimer avanza de a poco. En el turno de la IA no hace
        -- falta: la posicion cambia en cuanto juega.
        if not G.mateJob and not (G.aiMode and G.turn~=G.myColor) then
            local ctx=newCtx(G.board)
            local side,ep,cas=G.turn,epToSq(G.epTarget),casToMask(G.castling)
            G.mateJob=coroutine.create(function() return mateDistance(ctx,side,ep,cas) end)
        end
        MateLabel:SetText(""); return
    end
    if G.mate and G.mate>0 then
        if G.turn==G.myColor then
            MateLabel:SetText("|cFF66FF66"..format(L["MATE_YOU"],G.mate).."|r")
        else
            MateLabel:SetText("|cFFFF6666"..format(L["MATE_OPP"],G.mate).."|r")
        end
    else
        MateLabel:SetText("")
    end
end

-- ============================================================
-- SIDE PANEL (turn / opponent / undo visibility)
-- ============================================================
updateSidePanel = function()
    if OppLabel then
        if G.gameActive and not G.aiMode and G.opponent then
            OppLabel:SetText("|cFF00CCFF"..format(L["VS_PLAYER"],shortName(G.opponent)).."|r")
        else
            OppLabel:SetText("")
        end
    end
    if UndoBtn then
        if G.aiMode and G.gameActive and not G.gameOver and G.undo and #G.undo>0 then
            UndoBtn:Enable()
        else
            UndoBtn:Disable()
        end
    end
end

-- ============================================================
-- UPDATE BOARD
-- ============================================================
updateBoard = function()
    if not SquareBtns then return end
    for dr=1,8 do
        for dc=1,8 do
            local sq=SquareBtns[dr][dc]; if not sq then break end
            local br,bc=dispToBoard(dr,dc)
            local piece=G.board[br] and G.board[br][bc] or nil
            if (dr+dc)%2==0 then sq.bgTex:SetTexture(0.91,0.83,0.68,1)
            else                  sq.bgTex:SetTexture(0.43,0.27,0.10,1) end
            local hr,hg,hb,ha=0,0,0,0
            if G.lastFrom and G.lastFrom[1]==br and G.lastFrom[2]==bc then hr,hg,hb,ha=0.85,0.85,0.10,0.40
            elseif G.lastTo and G.lastTo[1]==br and G.lastTo[2]==bc then hr,hg,hb,ha=0.85,0.85,0.10,0.40 end
            if G.inCheck and piece==G.turn.."K" then hr,hg,hb,ha=0.90,0.10,0.10,0.65 end
            if G.selR==br and G.selC==bc then hr,hg,hb,ha=0.10,0.88,0.10,0.60 end
            for _,m in ipairs(G.validMoves) do
                if m.tr==br and m.tc==bc then
                    if piece then hr,hg,hb,ha=0.90,0.20,0.10,0.55
                    else hr,hg,hb,ha=0.15,0.35,0.90,0.45 end; break
                end
            end
            sq.hlTex:SetTexture(hr,hg,hb,ha)
            local texPath=getPieceTex(piece)
            if texPath then sq.pieceTex:SetTexture(texPath); sq.pieceTex:Show()
            else sq.pieceTex:SetTexture(nil); sq.pieceTex:Hide() end
        end
    end
    if TurnLabel then
        if G.gameActive then
            local tc=G.turn=="w" and "|cFFFFD700"..L["WHITE"].."|r" or "|cFFFF4400"..L["BLACK"].."|r"
            TurnLabel:SetText(format(L["TURN"],tc))
        else
            TurnLabel:SetText("|cFFAAAAAA"..L["NO_ACTIVE_GAME"].."|r")
        end
    end
    if StatusLabel then
        if G.gameOver then
            if G.winner=="draw" then
                local key=(G.drawReason=="repetition" and "DRAW_REPETITION")
                       or (G.drawReason=="fifty" and "DRAW_FIFTY")
                       or (G.drawReason=="material" and "DRAW_MATERIAL") or "STALEMATE"
                StatusLabel:SetText("|cFFAAAAAA"..L[key].."|r")
            else
                local wn=G.winner=="w" and "|cFFFFD700"..L["WHITE"].."|r" or "|cFFFF4400"..L["BLACK"].."|r"
                StatusLabel:SetText(format(L["CHECKMATE"],wn))
            end
        elseif G.inCheck then StatusLabel:SetText("|cFFFF3333"..L["CHECK"].."|r")
        elseif G.gameActive then
            if G.turn==G.myColor then StatusLabel:SetText("|cFF00FF00"..L["YOUR_TURN"].."|r")
            elseif G.aiMode then
                local d=DIFFICULTIES[G.diff] or DIFFICULTIES[3]
                StatusLabel:SetText(format(L["AI_THINKING"],"|cFF"..d.color..d.name.."|r"))
            else StatusLabel:SetText(L["OPP_TURN"]) end
        else StatusLabel:SetText(L["CHOOSE_MODE"]) end
    end
    updateSidePanel()
    updateMate()
    if API.onUpdate then API.onUpdate() end
end

clearBoardDisplay = function()
    if not SquareBtns then return end
    for dr=1,8 do
        for dc=1,8 do
            local sq=SquareBtns[dr][dc]; if not sq then break end
            if (dr+dc)%2==0 then sq.bgTex:SetTexture(0.91,0.83,0.68,1)
            else                  sq.bgTex:SetTexture(0.43,0.27,0.10,1) end
            sq.hlTex:SetTexture(0,0,0,0)
            sq.pieceTex:SetTexture(nil); sq.pieceTex:Hide()
        end
    end
    if TurnLabel  then TurnLabel:SetText("|cFFAAAAAA"..L["NO_ACTIVE_GAME"].."|r") end
    if OppLabel   then OppLabel:SetText("") end
    if StatusLabel then StatusLabel:SetText(L["CHOOSE_MODE"]) end
    if TimerLabel  then TimerLabel:SetText("|cFFAAAAAA"..L["TIME_NONE"].."|r") end
    if MateLabel   then MateLabel:SetText("") end
    updateSidePanel()
    if API.onUpdate then API.onUpdate() end
end

-- ============================================================
-- MOVE ALERT (minimap flash + sound)
-- ============================================================
local function alertMyTurn(fromName)
    if API.Alert then API.Alert() end          -- flash + sound (the transition ping)
    if API.onUpdate then API.onUpdate() end     -- refresh the persistent minimap border
    notify(format(L["N_YOUR_TURN_ALERT"], fromName or "?"))
end

-- ============================================================
-- SQUARE CLICK
-- ============================================================
local function onSquareClick(dr,dc)
    if not G.gameActive or G.gameOver then return end
    if G.turn~=G.myColor then return end
    if G.aiPending then return end
    if isPromotionOpen() then return end
    local br,bc=dispToBoard(dr,dc); local piece=G.board[br][bc]
    if G.selR then
        if br==G.selR and bc==G.selC then
            G.selR=nil; G.selC=nil; G.validMoves={}
        else
            local mv=nil
            for _,m in ipairs(G.validMoves) do if m.tr==br and m.tc==bc then mv=m; break end end
            if mv then
                local myGame = G
                local function play(promoLetter)
                    local wasPvP = (not myGame.aiMode) and myGame.opponent
                    if promoLetter then mv.promo=myGame.myColor..promoLetter end
                    executeMove(mv,myGame)
                    if wasPvP then
                        local sp=mv.sp or ""
                        local msg="MOVE:"..mv.fr..","..mv.fc..","..mv.tr..","..mv.tc..","..sp
                        -- la pieza elegida va en un campo extra; versiones viejas lo
                        -- ignoran y coronan a dama
                        if promoLetter then msg=msg..","..promoLetter end
                        SendAddonMessage(PREFIX,msg,"WHISPER",myGame.opponent)
                    end
                    if myGame.aiMode and not myGame.gameOver then myGame.aiPending=true end
                    if myGame.gameOver and not myGame.aiMode then showRematchPopup(myGame) end
                    if myGame==G then updateBoard() else updateTabs() end
                end
                if typ(G.board[mv.fr][mv.fc])=="P" and (mv.tr==8 or mv.tr==1) then
                    -- coronacion: el jugador elige la pieza
                    G.selR=nil; G.selC=nil; G.validMoves={}
                    updateBoard()
                    local fromPiece=G.board[mv.fr][mv.fc]
                    showPromotion(G.myColor,function(letter)
                        -- la partida pudo cambiar mientras el popup estaba abierto
                        if myGame.gameOver or myGame.turn~=myGame.myColor
                           or myGame.board[mv.fr][mv.fc]~=fromPiece then return end
                        play(letter)
                    end)
                    return
                end
                play(nil)
                return
            else
                if piece and col(piece)==G.myColor then
                    G.selR=br; G.selC=bc
                    G.validMoves=legalMoves(G.board,br,bc,G.epTarget,G.castling)
                else G.selR=nil; G.selC=nil; G.validMoves={} end
            end
        end
    else
        if piece and col(piece)==G.myColor then
            G.selR=br; G.selC=bc
            G.validMoves=legalMoves(G.board,br,bc,G.epTarget,G.castling)
        end
    end
    updateBoard()
end

-- ============================================================
-- NEW GAME VS AI  (uses the current tab)
-- ============================================================
local function newGameVsAI(myColor)
    hidePromotion()
    initBoard()
    G.myColor=myColor or "w"; G.gameActive=true; G.aiMode=true
    G.opponent=nil; G.diff=defaultDiff
    G.aiPending=(G.myColor=="b")
    if ChessFrame then ChessFrame:Show() end
    updateTabs(); updateBoard(); updateDiffButtons()
    saveAllGames()
    local d=DIFFICULTIES[G.diff] or DIFFICULTIES[3]
    notify(format(L["N_NEW_AI"],"|cFF"..d.color..d.name.."|r", G.myColor=="w" and L["WHITE"] or L["BLACK"]))
end

-- ============================================================
-- RESTART / RESIGN / ABANDON / UNDO
-- ============================================================
local function doLocalRestart()
    local wasAI    = G.aiMode
    local myColor  = G.myColor
    local opponent = G.opponent
    local diff     = G.diff
    hidePromotion()
    initBoard()
    G.myColor    = myColor; G.gameActive = true; G.aiMode = wasAI
    G.opponent   = wasAI and nil or opponent; G.diff = diff
    G.aiPending  = (myColor=="b" and wasAI) and true or false
    if ChessFrame then ChessFrame:Show() end
    updateTabs(); updateBoard()
    saveAllGames()
end

local function restartGame()
    if not G.gameActive then notify(L["N_NO_ACTIVE"]); return end
    if not G.aiMode and G.opponent then
        -- PvP: needs the opponent's agreement
        SendAddonMessage(PREFIX,"REQRESTART","WHISPER",G.opponent)
        notify(format(L["N_RESTART_REQ_SENT"],shortName(G.opponent)))
        return
    end
    doLocalRestart()
    notify(L["N_RESTARTED"])
end

local function resignGame()
    if not G.gameActive or G.gameOver then notify(L["N_NO_ACTIVE"]); return end
    G.gameOver=true; G.winner=opp(G.myColor)
    saveToHistory(G,"loss")
    if not G.aiMode and G.opponent then
        SendAddonMessage(PREFIX,"RESIGN","WHISPER",G.opponent) end
    saveAllGames()
    updateTabs(); updateBoard()
    notify(L["N_RESIGNED"])
    if not G.aiMode and G.opponent then showRematchPopup(G) end
end

local function abandonGame(silent)
    if not G.gameActive then if not silent then notify(L["N_NO_ACTIVE"]) end return end
    hidePromotion()
    if not G.gameOver then saveToHistory(G,"loss") end
    if not G.aiMode and G.opponent and not G.gameOver then
        SendAddonMessage(PREFIX, "RESIGN", "WHISPER", G.opponent)
    end
    games[activeIdx]=newGameState()
    G=games[activeIdx]
    if not silent then notify(L["N_ABANDONED"]) end
    saveAllGames()
    updateTabs(); updateSidePanel(); clearBoardDisplay()
end

local function undoMove()
    local g=G
    -- partida terminada: ya quedo en el historial, deshacer la duplicaria
    if not (g.aiMode and g.gameActive and not g.gameOver) then notify(L["N_NO_UNDO"]); return end
    if not g.undo or #g.undo==0 then notify(L["N_NO_UNDO"]); return end
    hidePromotion()
    local function restore()
        local s=table.remove(g.undo)
        -- la posicion que se deja ya no cuenta para la repeticion
        if g.reps and g.posKey and g.reps[g.posKey] then
            g.reps[g.posKey]=g.reps[g.posKey]-1
            if g.reps[g.posKey]<=0 then g.reps[g.posKey]=nil end
        end
        g.board=s.board; g.turn=s.turn; g.castling=s.castling
        g.epTarget=s.epTarget; g.lastFrom=s.lastFrom; g.lastTo=s.lastTo
        g.inCheck=s.inCheck; g.halfmove=s.halfmove or 0
        g.posKey=s.posKey or gameKey(g)
    end
    restore()
    if g.turn~=g.myColor and #g.undo>0 then restore() end
    g.gameOver=false; g.winner=nil; g.drawReason=nil
    g.thinker=nil; g.selR=nil; g.selC=nil; g.validMoves={}; g.mate=nil; g.mateJob=nil
    -- si jugas con negras y solo habia movido la IA, vuelve a ser su turno:
    -- antes quedaba trabada (nadie podia mover)
    g.aiPending=(g.turn~=g.myColor)
    updateTabs(); updateDiffButtons()
    updateBoard(); saveAllGames(); notify(L["N_MOVE_UNDONE"])
end

-- ============================================================
-- CHALLENGE HANDLING
-- ============================================================
local function doAcceptChallenge()
    local ch=pendingChallenge
    if not ch then notify(L["N_NO_PENDING"]); return end
    if countActiveGames()>=MAX_GAMES then notify(L["N_BUSY_TWO_GAMES"]); return end
    pendingChallenge=nil
    local idx=pickSlotForNew()
    setActiveSlot(idx)
    initBoard()
    G.myColor="b"; G.gameActive=true; G.aiMode=false
    G.opponent=ch; G.aiPending=false
    SendAddonMessage(PREFIX,"ACCEPT","WHISPER",ch)
    if ChessFrame then ChessFrame:Show() end
    updateTabs(); updateBoard(); saveAllGames()
    notify(format(L["N_YOU_ACCEPTED"],shortName(ch)))
end

local function doDeclineChallenge()
    if not pendingChallenge then notify(L["N_NO_PENDING"]); return end
    SendAddonMessage(PREFIX,"DECLINE","WHISPER",pendingChallenge)
    notify(format(L["N_YOU_DECLINED"],shortName(pendingChallenge)))
    pendingChallenge=nil
end

local function sendChallenge(target)
    if not target then return end
    if countActiveGames()>=MAX_GAMES then notify(L["N_BUSY_TWO_GAMES"]); return end
    outgoingChallenge=target
    SendAddonMessage(PREFIX,"CHALLENGE","WHISPER",target)
    notify(format(L["N_CHALLENGE_SENT"],shortName(target)))
end

-- ============================================================
-- HISTORY WINDOW (aligned columns)
-- ============================================================
local COLS = { x={6,34,110,190,326,388,446}, w={26,74,78,134,60,56,64} }

local function makeCol(parent,idx,text,color,fontObj)
    local fs=parent:CreateFontString(nil,"OVERLAY",fontObj or "GameFontNormalSmall")
    fs:SetPoint("LEFT",COLS.x[idx],0)
    fs:SetWidth(COLS.w[idx]); fs:SetJustifyH("LEFT")
    fs:SetText(color and ("|cFF"..color..text.."|r") or text)
    return fs
end

local function buildHistoryRows()
    if not HistoryFrame or not DB then return end
    local container = HistoryFrame.rowContainer
    for _,v in ipairs(HistoryFrame.rows or {}) do v:Hide() end
    HistoryFrame.rows = {}

    local wins,losses,draws,totalSec=0,0,0,0
    for _,e in ipairs(DB.history) do
        if e.result=="win" then wins=wins+1
        elseif e.result=="loss" then losses=losses+1
        else draws=draws+1 end
        totalSec=totalSec+(e.duration or 0)
    end
    HistoryFrame.statsText:SetText(format(L["HIST_STATS"],wins,losses,draws,formatSeconds(totalSec)))

    local rowH=22
    for i,e in ipairs(DB.history) do
        local row=CreateFrame("Frame",nil,container)
        row:SetSize(500,rowH)
        row:SetPoint("TOPLEFT",0,-(i-1)*rowH)
        local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints()
        if i%2==0 then bg:SetTexture(0.12,0.12,0.12,0.8) else bg:SetTexture(0.08,0.08,0.08,0.8) end

        local resultColor = e.result=="win" and "00FF00" or (e.result=="loss" and "FF4444" or "AAAAAA")
        local resultText  = e.result=="win" and L["HIST_WIN"] or (e.result=="loss" and L["HIST_LOSS"] or L["HIST_DRAW"])
        local modeText    = e.mode=="ai" and L["HIST_VS_AI"] or L["HIST_PVP"]
        local colorText   = e.myColor=="w" and L["WHITE"] or L["BLACK"]
        local oppStr, oppColor
        if e.mode=="ai" and e.diffName and e.diffColor then oppStr=e.diffName; oppColor=e.diffColor
        else oppStr=e.opponent or "?"; oppColor="00CCFF" end

        makeCol(row,1,tostring(i)..".","FFD700")
        makeCol(row,2,resultText,resultColor)
        makeCol(row,3,e.dateStr or "","FFFFFF")
        makeCol(row,4,oppStr,oppColor)
        makeCol(row,5,colorText,"DDDDDD")
        makeCol(row,6,modeText,"CCCCCC")
        makeCol(row,7,formatSeconds(e.duration or 0),"AAAAAA")
        table.insert(HistoryFrame.rows,row)
    end

    if #DB.history==0 then
        local lbl=container:CreateFontString(nil,"OVERLAY","GameFontNormal")
        lbl:SetPoint("CENTER",0,-20)
        lbl:SetText("|cFFAAAAAA"..L["HIST_EMPTY"].."|r")
        table.insert(HistoryFrame.rows,lbl)
    end
    container:SetHeight(math.max(1, #DB.history * rowH))
end

local function createHistoryFrame()
    if HistoryFrame then HistoryFrame:Show(); buildHistoryRows(); return end
    local f=CreateFrame("Frame","ChessHistoryFrame",UIParent)
    f:SetSize(560,400); f:SetPoint("CENTER",0,0)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving)
    f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true,tileSize=32,edgeSize=32,insets={left=8,right=8,top=8,bottom=8}
    })
    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",0,-14); title:SetText("|cFFFFD700"..L["HIST_TITLE"].."|r")
    local closeBtn=CreateFrame("Button",nil,f,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-3,-3); closeBtn:SetScript("OnClick",function() f:Hide() end)

    f.statsText=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.statsText:SetPoint("TOPLEFT",14,-42); f.statsText:SetWidth(530); f.statsText:SetJustifyH("LEFT")

    -- Column headers (same offsets as data rows -> aligned)
    local headerRow=CreateFrame("Frame",nil,f); headerRow:SetSize(500,18)
    headerRow:SetPoint("TOPLEFT",16,-76)
    local function hcol(idx,txt)
        local fs=headerRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fs:SetPoint("LEFT",COLS.x[idx],0); fs:SetWidth(COLS.w[idx]); fs:SetJustifyH("LEFT")
        fs:SetText("|cFFFFD700"..txt.."|r")
    end
    hcol(1,L["HDR_NUM"]); hcol(2,L["HDR_RESULT"]); hcol(3,L["HDR_DATE"])
    hcol(4,L["HDR_OPP"]); hcol(5,L["HDR_COLOR"]); hcol(6,L["HDR_MODE"]); hcol(7,L["HDR_TIME"])

    local sep=f:CreateTexture(nil,"ARTWORK")
    sep:SetSize(530,1); sep:SetPoint("TOPLEFT",14,-92); sep:SetTexture(0.5,0.4,0.2,0.6)

    local scrollFrame=CreateFrame("ScrollFrame","ChessHistoryScroll",f,"UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(520,262); scrollFrame:SetPoint("TOPLEFT",14,-96)
    local container=CreateFrame("Frame",nil,scrollFrame)
    container:SetSize(500,1); scrollFrame:SetScrollChild(container)
    f.rowContainer=container; f.rows={}

    local clearBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    clearBtn:SetSize(160,24); clearBtn:SetPoint("BOTTOMLEFT",14,12)
    clearBtn:SetText(L["HIST_CLEAR"])
    clearBtn:SetScript("OnClick",function()
        if DB then DB.history={} end; buildHistoryRows(); notify(L["HIST_CLEARED"])
    end)

    HistoryFrame=f
    buildHistoryRows()
    f:Show()
end

-- ============================================================
-- GENERIC CONFIRM POPUP (restart request / rematch)
-- ============================================================
local function createConfirmPopup()
    if ConfirmPopup then return end
    local f=CreateFrame("Frame","ChessConfirmPopup",UIParent)
    f:SetSize(320,140); f:SetPoint("CENTER",0,150)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true,tileSize=32,edgeSize=32,insets={left=11,right=11,top=11,bottom=11}
    }); f:Hide()
    f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    f.title:SetPoint("TOP",0,-14)
    f.msg=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    f.msg:SetPoint("TOP",0,-46); f.msg:SetWidth(280); f.msg:SetJustifyH("CENTER")
    local yes=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    yes:SetSize(120,26); yes:SetPoint("BOTTOMLEFT",22,16)
    local no=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    no:SetSize(120,26); no:SetPoint("BOTTOMRIGHT",-22,16)
    yes:SetScript("OnClick",function() f:Hide(); if f._onYes then f._onYes() end end)
    no:SetScript("OnClick",function() f:Hide(); if f._onNo then f._onNo() end end)
    f.yes=yes; f.no=no
    ConfirmPopup=f
end

local function showConfirm(title,msg,onYes,onNo,yesText,noText)
    createConfirmPopup()
    local f=ConfirmPopup
    f.title:SetText("|cFFFFD700"..title.."|r")
    f.msg:SetText(msg)
    f.yes:SetText(yesText or L["POPUP_YES"])
    f.no:SetText(noText or L["POPUP_NO"])
    f._onYes=onYes; f._onNo=onNo
    PlaySound(3439)
    f:Show()
end

showRematchPopup = function(g)
    if g.aiMode or not g.opponent or g.rematchOffered then return end
    g.rematchOffered=true
    local opp=g.opponent
    showConfirm(L["POPUP_REMATCH_TITLE"],
        format(L["POPUP_REMATCH_MSG"],shortName(opp)),
        function() sendChallenge(opp) end, nil)
end

-- ============================================================
-- PROMOTION PICKER (dama, torre, alfil o caballo)
-- ============================================================
local PromoFrame=nil
local PROMO_PIECES={"Q","R","B","N"}

isPromotionOpen = function() return PromoFrame~=nil and PromoFrame:IsShown() end
hidePromotion = function()
    if PromoFrame then PromoFrame._onPick=nil; PromoFrame:Hide() end
end
showPromotion = function(color,onPick)
    if not PromoFrame then
        local parent=BoardFrame or UIParent
        local f=CreateFrame("Frame",nil,parent)
        f:SetSize(SQ*4+28,SQ+28); f:SetPoint("CENTER")
        f:SetFrameLevel(parent:GetFrameLevel()+20)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile="Interface/DialogFrame/UI-DialogBox-Background",
            edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
            tile=true,tileSize=32,edgeSize=16,insets={left=5,right=5,top=5,bottom=5}
        })
        f.btns={}
        for i,letter in ipairs(PROMO_PIECES) do
            local b=CreateFrame("Button",nil,f)
            b:SetSize(SQ,SQ); b:SetPoint("LEFT",14+(i-1)*SQ,0)
            local bg=b:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints()
            if i%2==1 then bg:SetTexture(0.91,0.83,0.68,1) else bg:SetTexture(0.43,0.27,0.10,1) end
            local hl=b:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(0.10,0.88,0.10,0.35)
            local pt=b:CreateTexture(nil,"ARTWORK"); pt:SetSize(SQ-6,SQ-6); pt:SetPoint("CENTER"); b.pieceTex=pt
            b.letter=letter
            b:SetScript("OnClick",function(self)
                local cb=f._onPick; f._onPick=nil; f:Hide()
                if cb then cb(self.letter) end
            end)
            f.btns[i]=b
        end
        local close=CreateFrame("Button",nil,f,"UIPanelCloseButton")
        close:SetSize(24,24); close:SetPoint("TOPRIGHT",6,6)
        close:SetScript("OnClick",function() hidePromotion() end)
        -- clic derecho fuera de las piezas tambien cancela
        f:SetScript("OnMouseUp",function(self,btn) if btn=="RightButton" then hidePromotion() end end)
        PromoFrame=f
    end
    for _,b in ipairs(PromoFrame.btns) do b.pieceTex:SetTexture(getPieceTex(color..b.letter)) end
    PromoFrame._onPick=onPick
    PromoFrame:Show()
end

-- ============================================================
-- CHALLENGE POPUP
-- ============================================================
local function createChallengePopup()
    if ChallengePopup then return end
    local f=CreateFrame("Frame","ChessChallengePopup",UIParent)
    f:SetSize(320,150); f:SetPoint("CENTER",0,120)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true,tileSize=32,edgeSize=32,insets={left=11,right=11,top=11,bottom=11}
    }); f:Hide()
    local icon=f:CreateTexture(nil,"ARTWORK")
    icon:SetSize(40,40); icon:SetPoint("TOPLEFT",18,-16)
    icon:SetTexture("Interface\\Icons\\Achievement_pvp_a_01")
    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",0,-14); title:SetText("|cFFFFD700"..L["POPUP_TITLE"].."|r")
    f.msgText=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    f.msgText:SetPoint("TOP",0,-46); f.msgText:SetWidth(280); f.msgText:SetJustifyH("CENTER")
    f.timerText=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.timerText:SetPoint("BOTTOM",0,50); f.timerText:SetTextColor(0.8,0.8,0.8)
    local acceptBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    acceptBtn:SetSize(130,26); acceptBtn:SetPoint("BOTTOMLEFT",18,14)
    acceptBtn:SetText(L["POPUP_ACCEPT"])
    acceptBtn:SetScript("OnClick",function() f._ticking=false; f:Hide(); doAcceptChallenge() end)
    local declineBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    declineBtn:SetSize(130,26); declineBtn:SetPoint("BOTTOMRIGHT",-18,14)
    declineBtn:SetText(L["POPUP_DECLINE"])
    declineBtn:SetScript("OnClick",function() f._ticking=false; f:Hide(); doDeclineChallenge() end)
    f:SetScript("OnUpdate",function(self,dt)
        if not self._ticking then return end
        self._elapsed=(self._elapsed or 0)+dt
        if self._elapsed>=1 then
            self._elapsed=0; self._countdown=(self._countdown or 30)-1
            if self._countdown<=0 then
                self._ticking=false; self:Hide()
                if pendingChallenge then
                    SendAddonMessage(PREFIX,"DECLINE","WHISPER",pendingChallenge)
                    notify(format(L["N_EXPIRED"],shortName(pendingChallenge)))
                    pendingChallenge=nil
                end
            else
                self.timerText:SetText(format(L["POPUP_EXPIRES"],self._countdown))
                if self._countdown<=5 then self.timerText:SetTextColor(1,0.2,0.2)
                else self.timerText:SetTextColor(0.8,0.8,0.8) end
            end
        end
    end)
    f.acceptBtn=acceptBtn; f.declineBtn=declineBtn
    ChallengePopup=f
end

local function showChallengePopup(challenger,busy)
    createChallengePopup()
    local f=ChallengePopup
    f._countdown=30; f._ticking=true; f._elapsed=0
    f.timerText:SetText(format(L["POPUP_EXPIRES"],30)); f.timerText:SetTextColor(0.8,0.8,0.8)
    if busy then
        f.msgText:SetText(format(L["POPUP_BUSY"],shortName(challenger)))
        f.acceptBtn:Hide()
        f.declineBtn:ClearAllPoints(); f.declineBtn:SetSize(261,26); f.declineBtn:SetPoint("BOTTOM",0,14)
        PlaySound(882)
    else
        f.msgText:SetText(format(L["POPUP_MSG"],shortName(challenger)))
        f.acceptBtn:Show(); f.acceptBtn:SetSize(130,26)
        f.acceptBtn:ClearAllPoints(); f.acceptBtn:SetPoint("BOTTOMLEFT",18,14)
        f.declineBtn:ClearAllPoints(); f.declineBtn:SetSize(130,26); f.declineBtn:SetPoint("BOTTOMRIGHT",-18,14)
        PlaySound(3439)
    end
    f:Show()
end

-- ============================================================
-- ESCAPE CLOSE TOGGLE
-- ============================================================
local function applyEscClose()
    -- remove any existing entry
    for i=#UISpecialFrames,1,-1 do
        if UISpecialFrames[i]=="ChessMainFrame" then table.remove(UISpecialFrames,i) end
    end
    if DB and DB.settings and DB.settings.escClose then
        table.insert(UISpecialFrames,"ChessMainFrame")
    end
end

-- ============================================================
-- MAIN UI
-- ============================================================
local function createUI()
    local boardPx=SQ*8; local labelSz=18
    local panelW=195
    local TABH=TAB_H
    local frameW=labelSz+boardPx+panelW+30
    local frameH=boardPx+labelSz+62+TABH   -- close to the original height

    ChessFrame=CreateFrame("Frame","ChessMainFrame",UIParent)
    ChessFrame:SetSize(frameW,frameH); ChessFrame:SetPoint("CENTER")
    ChessFrame:SetMovable(true); ChessFrame:EnableMouse(true)
    ChessFrame:RegisterForDrag("LeftButton")
    ChessFrame:SetScript("OnDragStart",ChessFrame.StartMoving)
    ChessFrame:SetScript("OnDragStop",ChessFrame.StopMovingOrSizing)
    ChessFrame:SetFrameStrata("DIALOG"); ChessFrame:SetToplevel(true)
    ChessFrame:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true,tileSize=32,edgeSize=32,insets={left=8,right=8,top=8,bottom=8}
    })

    local title=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetWidth(frameW-60); title:SetPoint("TOP",0,-11); title:SetJustifyH("CENTER")
    title:SetText("|cFFFFD700"..L["TITLE"].."|r")

    local closeBtn=CreateFrame("Button",nil,ChessFrame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-3,-3)
    closeBtn:SetScript("OnClick",function() ChessFrame:Hide(); if HistoryFrame then HistoryFrame:Hide() end end)

    -- --- Tab strip (Chrome style) ---
    local tabStrip=CreateFrame("Frame",nil,ChessFrame)
    tabStrip:SetSize(boardPx,TABH); tabStrip:SetPoint("TOPLEFT",labelSz+14,-30)
    for i=1,MAX_GAMES do
        local tf=CreateFrame("Button",nil,tabStrip)
        tf:SetSize(108,TABH)
        local bg=tf:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0.22,0.18,0.11,0.9)
        local top=tf:CreateTexture(nil,"BORDER"); top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetTexture(0.6,0.45,0.15,0.9)
        local txt=tf:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        txt:SetPoint("LEFT",8,0); txt:SetWidth(80); txt:SetJustifyH("LEFT")
        local closeB=CreateFrame("Button",nil,tf)
        closeB:SetSize(16,16); closeB:SetPoint("RIGHT",-3,0)
        local cx=closeB:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); cx:SetAllPoints(); cx:SetJustifyH("CENTER"); cx:SetText("|cFFFF6666x|r")
        closeB:SetScript("OnClick",function() closeTab(i) end)
        closeB:SetScript("OnEnter",function(s) GameTooltip:SetOwner(s,"ANCHOR_RIGHT"); GameTooltip:AddLine(L["TAB_CLOSE_TT"],1,1,1); GameTooltip:Show() end)
        closeB:SetScript("OnLeave",function() GameTooltip:Hide() end)
        tf:SetScript("OnClick",function() switchToTab(i) end)
        TabWidgets[i]={frame=tf,bg=bg,text=txt,close=closeB}
    end
    PlusBtn=CreateFrame("Button",nil,tabStrip)
    PlusBtn:SetSize(TABH,TABH)
    local pbg=PlusBtn:CreateTexture(nil,"BACKGROUND"); pbg:SetAllPoints(); pbg:SetTexture(0.18,0.15,0.09,0.9)
    local ptx=PlusBtn:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); ptx:SetAllPoints(); ptx:SetJustifyH("CENTER"); ptx:SetText("|cFFFFD700+|r")
    PlusBtn:SetScript("OnClick",function() openNewTab() end)
    PlusBtn:SetScript("OnEnter",function(s) GameTooltip:SetOwner(s,"ANCHOR_RIGHT"); GameTooltip:AddLine(L["TAB_NEW_TT"],1,1,1); GameTooltip:Show() end)
    PlusBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    -- --- Board ---
    local boardTop=30+TABH+2
    local boardFrame=CreateFrame("Frame",nil,ChessFrame)
    boardFrame:SetSize(boardPx,boardPx); boardFrame:SetPoint("TOPLEFT",labelSz+14,-boardTop)
    BoardFrame=boardFrame
    local border=boardFrame:CreateTexture(nil,"BACKGROUND")
    border:SetPoint("TOPLEFT",-4,4); border:SetPoint("BOTTOMRIGHT",4,-4); border:SetTexture(0.12,0.07,0.01,1)

    SquareBtns={}
    for dr=1,8 do
        SquareBtns[dr]={}
        for dc=1,8 do
            local sq=CreateFrame("Button",nil,boardFrame)
            sq:SetSize(SQ,SQ); sq:SetPoint("TOPLEFT",(dc-1)*SQ,-(dr-1)*SQ)
            local bg=sq:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); sq.bgTex=bg
            local hl=sq:CreateTexture(nil,"BORDER"); hl:SetAllPoints(); sq.hlTex=hl
            local pt=sq:CreateTexture(nil,"ARTWORK")
            pt:SetSize(SQ-6,SQ-6); pt:SetPoint("CENTER"); pt:Hide(); sq.pieceTex=pt
            sq.dispR=dr; sq.dispC=dc
            sq:SetScript("OnClick",function(self) onSquareClick(self.dispR,self.dispC) end)
            sq:SetScript("OnEnter",function(self) self.hlTex:SetAlpha(0.75) end)
            sq:SetScript("OnLeave",function(self) self.hlTex:SetAlpha(1.0) end)
            SquareBtns[dr][dc]=sq
        end
    end
    local FILES="abcdefgh"
    for dc=1,8 do
        local lbl=boardFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetSize(SQ,labelSz); lbl:SetPoint("TOPLEFT",(dc-1)*SQ,-boardPx)
        lbl:SetJustifyH("CENTER"); lbl:SetText("|cFFBBAA88"..FILES:sub(dc,dc).."|r")
    end
    for dr=1,8 do
        local lbl=boardFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetSize(labelSz,SQ); lbl:SetPoint("TOPRIGHT",boardFrame,"TOPLEFT",-2,-(dr-1)*SQ)
        lbl:SetJustifyH("RIGHT"); lbl:SetJustifyV("MIDDLE"); lbl:SetText("|cFFBBAA88"..(9-dr).."|r")
    end

    -- Floating notice over the board bottom (no extra window height)
    NoticeLabel=boardFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    NoticeLabel:SetPoint("BOTTOM",boardFrame,"BOTTOM",0,6); NoticeLabel:SetWidth(boardPx-10)
    NoticeLabel:SetJustifyH("CENTER"); NoticeLabel:SetText("")

    -- --- Side panel ---
    local px=labelSz+boardPx+20
    local function Y(y) return y end

    TurnLabel=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    TurnLabel:SetPoint("TOPLEFT",px,Y(-54)); TurnLabel:SetWidth(panelW-4); TurnLabel:SetJustifyH("LEFT")
    TurnLabel:SetText("|cFFAAAAAA"..L["NO_ACTIVE_GAME"].."|r")

    OppLabel=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    OppLabel:SetPoint("TOPLEFT",px,Y(-70)); OppLabel:SetWidth(panelW-4); OppLabel:SetJustifyH("LEFT"); OppLabel:SetText("")

    StatusLabel=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    StatusLabel:SetPoint("TOPLEFT",px,Y(-86)); StatusLabel:SetWidth(panelW-4); StatusLabel:SetJustifyH("LEFT")
    StatusLabel:SetText(L["CHOOSE_MODE"])

    TimerLabel=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    TimerLabel:SetPoint("TOPLEFT",px,Y(-103)); TimerLabel:SetWidth(panelW-4); TimerLabel:SetJustifyH("LEFT")
    TimerLabel:SetText("|cFFAAAAAA"..L["TIME_NONE"].."|r")

    MateLabel=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    MateLabel:SetPoint("TOPLEFT",px,Y(-118)); MateLabel:SetWidth(panelW-4); MateLabel:SetJustifyH("LEFT"); MateLabel:SetText("")

    local function makeSep(y)
        local s=ChessFrame:CreateTexture(nil,"ARTWORK")
        s:SetSize(panelW-4,1); s:SetPoint("TOPLEFT",px,Y(y)); s:SetTexture(0.5,0.4,0.2,0.5)
    end
    local function makeBtn(label,yOff,fn,h)
        local b=CreateFrame("Button",nil,ChessFrame,"UIPanelButtonTemplate")
        b:SetSize(panelW-4,h or 22); b:SetPoint("TOPLEFT",px,Y(yOff))
        b:SetText(label); b:SetScript("OnClick",fn); return b
    end

    makeSep(-133)
    local diffTitle=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    diffTitle:SetPoint("TOPLEFT",px,Y(-139)); diffTitle:SetWidth(panelW-4)
    diffTitle:SetText("|cFFFFD700"..L["DIFF_TITLE"].."|r")

    local bW3=math.floor((panelW-4)/3)-1
    local bW2=math.floor((panelW-4)/2)-1
    local diffLayout={
        {i=1,x=0,y=-152,w=bW3},{i=2,x=bW3+1,y=-152,w=bW3},{i=3,x=(bW3+1)*2,y=-152,w=bW3},
        {i=4,x=0,y=-174,w=bW2},{i=5,x=bW2+1,y=-174,w=bW2},
    }
    DiffBtns={}
    for _,lay in ipairs(diffLayout) do
        local i=lay.i; local d=DIFFICULTIES[i]
        local btn=CreateFrame("Button",nil,ChessFrame,"UIPanelButtonTemplate")
        btn:SetSize(lay.w,20); btn:SetPoint("TOPLEFT",px+lay.x,Y(lay.y))
        btn:SetScript("OnClick",function()
            defaultDiff=i
            if G.aiMode and G.gameActive and not G.gameOver then G.diff=i end
            updateDiffButtons(); notify(format(L["N_DIFF_SET"],"|cFF"..d.color..d.name.."|r"))
        end)
        btn:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFF"..d.color..d.name.."|r",1,1,1)
            GameTooltip:AddLine(d.desc,0.8,0.8,0.8)
            if d.mode=="minimax" then GameTooltip:AddLine(format(L["DIFF_DEPTH"],d.depth),0.6,0.8,1) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave",function() GameTooltip:Hide() end)
        DiffBtns[i]=btn
    end
    updateDiffButtons()

    makeSep(-198)
    makeBtn(L["BTN_NEW_WHITE"],-204,function() newGameVsAI("w") end)
    makeBtn(L["BTN_NEW_BLACK"],-228,function() newGameVsAI("b") end)
    makeSep(-253)
    makeBtn(L["BTN_CHALLENGE"],-259,function()
        local target=UnitName("target")
        if not target or not UnitIsPlayer("target") then notify(L["N_SELECT_PLAYER"]); return end
        if target==UnitName("player") then notify(L["N_NO_SELF"]); return end
        sendChallenge(target)
    end)
    UndoBtn=makeBtn(L["BTN_UNDO"],-283,function() undoMove() end)
    makeBtn(L["BTN_RESTART"],-307,function() restartGame() end)
    makeBtn(L["BTN_RESIGN"],-331,function() resignGame() end)
    makeBtn(L["BTN_ABANDON"],-355,function() abandonGame(false) end)
    makeBtn(L["BTN_HISTORY"],-379,function() createHistoryFrame() end)

    makeSep(-403)
    local legend=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    legend:SetPoint("TOPLEFT",px,Y(-408)); legend:SetWidth(panelW-4); legend:SetJustifyH("LEFT")
    legend:SetText(L["LEGEND"])

    ArenaCheck=CreateFrame("CheckButton",nil,ChessFrame,"UICheckButtonTemplate")
    ArenaCheck:SetSize(22,22); ArenaCheck:SetPoint("TOPLEFT",px,Y(-440))
    local acL=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    acL:SetPoint("LEFT",ArenaCheck,"RIGHT",2,0); acL:SetWidth(panelW-24); acL:SetJustifyH("LEFT"); acL:SetText(L["ARENA_MINIMIZE"])
    ArenaCheck:SetScript("OnClick",function(self) if DB and DB.settings then DB.settings.arenaMinimize=self:GetChecked() and true or false end end)
    ArenaCheck:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(L["ARENA_MINIMIZE"],1,1,1); GameTooltip:AddLine(L["ARENA_TOOLTIP"],0.8,0.8,0.8,true); GameTooltip:Show() end)
    ArenaCheck:SetScript("OnLeave",function() GameTooltip:Hide() end)

    EscCheck=CreateFrame("CheckButton",nil,ChessFrame,"UICheckButtonTemplate")
    EscCheck:SetSize(22,22); EscCheck:SetPoint("TOPLEFT",px,Y(-462))
    local ecL=ChessFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    ecL:SetPoint("LEFT",EscCheck,"RIGHT",2,0); ecL:SetWidth(panelW-24); ecL:SetJustifyH("LEFT"); ecL:SetText(L["ESC_CLOSE"])
    EscCheck:SetScript("OnClick",function(self)
        if DB and DB.settings then DB.settings.escClose=self:GetChecked() and true or false end
        applyEscClose()
    end)
    EscCheck:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(L["ESC_CLOSE"],1,1,1); GameTooltip:AddLine(L["ESC_TOOLTIP"],0.8,0.8,0.8,true); GameTooltip:Show() end)
    EscCheck:SetScript("OnLeave",function() GameTooltip:Hide() end)

    -- AI timer: the search runs inside a coroutine that is resumed one small
    -- time-slice per frame, so the game keeps drawing while the AI thinks
    -- (no more freeze). No ping/flash for AI moves (board is on screen).
    local function aiFallback(g)
        local ms=allLegalMoves(g.board,opp(g.myColor),g.epTarget,g.castling)
        return (#ms>0) and ms[math.random(#ms)] or nil
    end
    -- Presupuesto por frame: ~35% del tiempo de un frame (entre 3 y 8 ms),
    -- asi a 60 FPS la IA usa ~6 ms y a 30 FPS no se come el frame entero.
    local function startSlice()
        local fps=GetFramerate and GetFramerate() or 60
        if not fps or fps<1 then fps=60 end
        local b=350/fps
        if b<3 then b=3 elseif b>8 then b=8 end
        SEARCH.budget=b
        SEARCH.nodes=0; SEARCH.sliceStart=profclock()
    end
    local aiTimer=CreateFrame("Frame"); aiTimer.elapsed=0
    aiTimer:SetScript("OnUpdate",function(self,dt)
        local g=G
        if not (g.aiPending and g.aiMode and g.gameActive and not g.gameOver) then
            self.elapsed=0
            -- sin IA pensando: avanzar el calculo del "mate en N" (solo con el tablero a la vista)
            local job=g.mateJob
            if job and ChessFrame and ChessFrame:IsShown() then
                startSlice()
                local ok,res=coroutine.resume(job)
                if g.mateJob==job and (not ok or coroutine.status(job)=="dead") then
                    g.mateJob=nil
                    g.mate=(ok and res) or 0
                    if g==G then updateMate() end
                end
            end
            return
        end
        if not g.thinker then
            -- short "thinking" delay for feel, then spawn the search
            self.elapsed=self.elapsed+dt
            local waitTime=(g.diff>=4) and 0.15 or 0.45
            if self.elapsed>=waitTime then
                self.elapsed=0
                g.thinker=coroutine.create(function() return getAIMove(g) end)
            end
            return
        end
        -- resume the search for one slice, then let the frame render
        startSlice()
        local th=g.thinker
        local ok,res=coroutine.resume(th)
        -- si deshacer/reiniciar descarto esta busqueda mientras corria, ignorarla
        if g.thinker~=th then return end
        if not ok or coroutine.status(th)=="dead" then
            local mv = ok and res or nil
            -- mostrar el error en vez de tragarlo (se juega igual una al azar)
            if not ok and geterrorhandler then geterrorhandler()(res) end
            g.thinker=nil; g.aiPending=false
            if not mv then mv=aiFallback(g) end
            if mv then executeMove(mv,g); updateBoard() end
        end
    end)

    -- Clock / notice fade / periodic save
    local clockTimer=CreateFrame("Frame"); clockTimer.elapsed=0
    clockTimer:SetScript("OnUpdate",function(self,dt)
        self.elapsed=self.elapsed+dt
        if self.elapsed>=1 then
            self.elapsed=0
            if TimerLabel then
                if G.gameActive and not G.gameOver then
                    TimerLabel:SetText("|cFFFFD700"..format(L["TIME"],formatSeconds(gElapsed(G))).."|r")
                elseif G.gameOver then
                    TimerLabel:SetText("|cFFAAAAAA"..format(L["TIME"],formatSeconds(gElapsed(G))).."|r")
                else
                    TimerLabel:SetText("|cFFAAAAAA"..L["TIME_NONE"].."|r")
                end
            end
            if noticeExpire>0 and time()>=noticeExpire then
                if NoticeLabel then NoticeLabel:SetText("") end; noticeExpire=0
            end
            self._saveCount=(self._saveCount or 0)+1
            if self._saveCount>=30 then self._saveCount=0; saveAllGames() end
        end
    end)

    -- Arena "gates open" detection.
    -- The board is hidden the moment the match STARTS (gates open), never on
    -- entering the arena. Two independent signals are used for reliability:
    --   1) the "Arena Preparation" aura disappearing (matched by icon AND by
    --      EN/ES name, so it works whatever the client language), and
    --   2) the "The Arena battle has begun!" system message.
    local function hasPrepAura()
        for i=1,40 do
            local name,_,icon = UnitBuff("player", i)
            if not name then break end
            if icon and string.find(icon,"Spell_Nature_TimeStop") then return true end
            local ln=string.lower(name)
            if string.find(ln,"preparation") or string.find(ln,"preparaci") then return true end
        end
        return false
    end
    API._gatesOpen=function()
        if DB and DB.settings and DB.settings.arenaMinimize and ChessFrame and ChessFrame:IsShown() then
            ChessFrame:Hide()
        end
    end
    local arenaWatch=CreateFrame("Frame"); arenaWatch.t=0; arenaWatch.hadPrep=false; arenaWatch:Hide()
    arenaWatch:SetScript("OnUpdate",function(self,dt)
        self.t=self.t+dt
        if self.t<0.5 then return end
        self.t=0
        local prep=hasPrepAura()
        if self.hadPrep and not prep then
            API._gatesOpen()   -- prep aura removed -> gates just opened
            self:Hide()
        end
        self.hadPrep=prep
    end)
    API._startArenaWatch=function()
        arenaWatch.hadPrep=hasPrepAura(); arenaWatch.t=0; arenaWatch:Show()
    end
    API._stopArenaWatch=function() arenaWatch:Hide() end

    ChessFrame:Hide()
    clearBoardDisplay()   -- draw empty board immediately
end

-- ============================================================
-- SHARED API FOR MINIMAP
-- ============================================================
API.GetState = function()
    return { active=G.gameActive and not G.gameOver, myTurn=(G.turn==G.myColor),
             aiMode=G.aiMode, opponent=shortName(G.opponent) }
end
-- True while it's your move in any open PvP game (drives the minimap border).
API.PendingPvPTurn = function()
    for i=1,openTabs do
        local g=games[i]
        if g and g.gameActive and not g.gameOver and not g.aiMode and g.turn==g.myColor then
            return true
        end
    end
    return false
end
API.ToggleBoard = function()
    if not ChessFrame then return end
    if ChessFrame:IsShown() then ChessFrame:Hide() else ChessFrame:Show() end
end
API.ShowBoard = function() if ChessFrame then ChessFrame:Show() end end

-- ============================================================
-- EVENTS
-- ============================================================
local eventFrame=CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")

eventFrame:SetScript("OnEvent",function(self,event,a1,a2,a3,a4)
    if event=="ADDON_LOADED" and a1==ADDON_NAME then
        ChessDB = ChessDB or {}
        ChessDB.history  = ChessDB.history  or {}
        ChessDB.settings = ChessDB.settings or {}
        if ChessDB.settings.escClose==nil then ChessDB.settings.escClose=true end
        DB = ChessDB

        createUI()
        applyEscClose()

        if ArenaCheck then ArenaCheck:SetChecked(DB.settings.arenaMinimize and true or false) end
        if EscCheck then EscCheck:SetChecked(DB.settings.escClose and true or false) end

        local restored=false
        if DB.games then
            local savedActive=DB.activeIdx or 1
            if savedActive<1 or savedActive>MAX_GAMES then savedActive=1 end
            for i=1,MAX_GAMES do
                if DB.games[i] then deserializeInto(games[i],DB.games[i], i==savedActive); restored=true end
            end
            openTabs = DB.openTabs or 1
            if openTabs<1 then openTabs=1 end
            if openTabs>MAX_GAMES then openTabs=MAX_GAMES end
            -- make sure every restored game has a visible tab
            for i=1,MAX_GAMES do
                if games[i] and games[i].gameActive and i>openTabs then openTabs=i end
            end
            activeIdx=savedActive
            if not (games[activeIdx] and games[activeIdx].gameActive) then
                for i=1,MAX_GAMES do if games[i] and games[i].gameActive then activeIdx=i; break end end
            end
            G=games[activeIdx]; resumeGame(G)
        end

        updateTabs(); updateDiffButtons(); updateSidePanel()
        if restored then
            if ChessFrame then ChessFrame:Show() end
            updateBoard(); notify(L["N_GAME_LOADED"])
        end

    elseif event=="PLAYER_ENTERING_WORLD" then
        local _, instanceType = IsInInstance()
        if instanceType=="arena" then
            if API._startArenaWatch then API._startArenaWatch() end   -- arm the gates-open watch
        else
            if API._stopArenaWatch then API._stopArenaWatch() end
        end

    elseif event=="CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        -- Second, independent "gates open" signal: the battle-begins message.
        local _, instanceType = IsInInstance()
        if instanceType=="arena" then
            local m=string.lower(a1 or "")
            if string.find(m,"begun") or string.find(m,"begin")
               or string.find(m,"comenzado") or string.find(m,"comienza") then
                if API._gatesOpen then API._gatesOpen() end
            end
        end

    elseif event=="PLAYER_LOGOUT" then
        saveAllGames()

    elseif event=="CHAT_MSG_ADDON" then
        local prefix,msg,channel,sender=a1,a2,a3,a4
        if prefix~=PREFIX then return end
        local sName=shortName(sender)
        if sName==UnitName("player") then return end

        if msg=="CHALLENGE" then
            pendingChallenge=sName
            showChallengePopup(sName, countActiveGames()>=MAX_GAMES)
            notify(format(L["N_CHALLENGE_RECV"],sName))

        elseif msg=="ACCEPT" then
            if outgoingChallenge and shortName(outgoingChallenge)==sName then
                outgoingChallenge=nil
                local idx=pickSlotForNew(); setActiveSlot(idx)
                initBoard()
                G.myColor="w"; G.gameActive=true; G.aiMode=false; G.opponent=sName; G.aiPending=false
                if ChessFrame then ChessFrame:Show() end
                updateTabs(); updateBoard(); saveAllGames()
                notify(format(L["N_ACCEPTED_BY"],sName))
            end

        elseif msg=="DECLINE" then
            if outgoingChallenge and shortName(outgoingChallenge)==sName then
                outgoingChallenge=nil; notify(format(L["N_DECLINED_BY"],sName))
            end

        elseif msg=="REQRESTART" then
            for i=1,MAX_GAMES do
                local g=games[i]
                if g and g.gameActive and not g.aiMode and shortName(g.opponent)==sName then
                    showConfirm(L["POPUP_RESTART_TITLE"], format(L["POPUP_RESTART_MSG"],sName),
                        function()
                            SendAddonMessage(PREFIX,"RESTARTOK","WHISPER",g.opponent)
                            if i~=activeIdx then setActiveSlot(i) end
                            doLocalRestart(); notify(L["N_RESTART_AGREED"])
                        end,
                        function() SendAddonMessage(PREFIX,"RESTARTNO","WHISPER",g.opponent) end)
                    break
                end
            end

        elseif msg=="RESTARTOK" then
            for i=1,MAX_GAMES do
                local g=games[i]
                if g and g.gameActive and not g.aiMode and shortName(g.opponent)==sName then
                    if i~=activeIdx then setActiveSlot(i) end
                    doLocalRestart(); notify(L["N_RESTART_AGREED"]); break
                end
            end

        elseif msg=="RESTARTNO" then
            notify(format(L["N_RESTART_DECLINED"],sName))

        elseif msg:sub(1,5)=="MOVE:" then
            local fr,fc,tr,tc,rest=msg:match("^MOVE:(%d+),(%d+),(%d+),(%d+),(.*)$")
            fr,fc,tr,tc=tonumber(fr),tonumber(fc),tonumber(tr),tonumber(tc)
            -- campo extra opcional con la pieza de coronacion (Q/R/B/N)
            local promoLetter=rest and rest:match(",([QRBN])$")
            if fr and fc and tr and tc then
                for i=1,MAX_GAMES do
                    local g=games[i]
                    if g and g.gameActive and not g.gameOver and not g.aiMode
                       and shortName(g.opponent)==sName and g.turn~=g.myColor then
                        -- solo se acepta si es legal aca; el tipo especial (enroque,
                        -- al paso) se toma de nuestra generacion, no del mensaje
                        local mv=nil
                        if inb(fr,fc) and inb(tr,tc) and g.board[fr][fc] and col(g.board[fr][fc])==g.turn then
                            for _,m in ipairs(legalMoves(g.board,fr,fc,g.epTarget,g.castling)) do
                                if m.tr==tr and m.tc==tc then mv=m; break end
                            end
                        end
                        if not mv then break end
                        if promoLetter and mv.promo then mv.promo=g.turn..promoLetter end
                        executeMove(mv,g)
                        if i==activeIdx then updateBoard() else updateTabs() end
                        if g.gameOver then
                            if g.winner=="draw" then notify(L["N_DRAW"])
                            else notify(g.winner==g.myColor and L["N_YOU_WIN"] or L["N_YOU_LOSE"]) end
                            showRematchPopup(g)
                        else
                            alertMyTurn(sName)
                        end
                        break
                    end
                end
            end

        elseif msg=="RESIGN" then
            for i=1,MAX_GAMES do
                local g=games[i]
                if g and g.gameActive and not g.gameOver and not g.aiMode
                   and shortName(g.opponent)==sName then
                    g.gameOver=true; g.winner=g.myColor
                    saveToHistory(g,"win"); saveAllGames()
                    if i==activeIdx then updateBoard() end
                    updateTabs(); notify(format(L["N_OPP_RESIGNED"],sName))
                    showRematchPopup(g)
                    break
                end
            end
        end
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================
local function slashCmd(msg)
    msg=(msg or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if msg=="" or msg=="open" or msg=="abrir" then
        API.ToggleBoard()
    elseif msg=="accept" or msg=="aceptar" then doAcceptChallenge()
    elseif msg=="decline" or msg=="rechazar" then doDeclineChallenge()
    elseif msg=="resign" or msg=="rendirse" then resignGame()
    elseif msg=="restart" or msg=="reiniciar" then restartGame()
    elseif msg=="undo" or msg=="deshacer" then undoMove()
    elseif msg=="history" or msg=="historial" then createHistoryFrame()
    elseif msg:match("^tab%s+(%d)$") then
        local n=tonumber(msg:match("(%d)$"))
        if n and n>=1 and n<=MAX_GAMES then
            if n>openTabs then openNewTab() else switchToTab(n) end
        end
    elseif msg:match("^dif%s+(%d)$") or msg:match("^diff%s+(%d)$") then
        local n=tonumber(msg:match("(%d)$"))
        if n and DIFFICULTIES[n] then
            defaultDiff=n
            if G.aiMode and G.gameActive and not G.gameOver then G.diff=n end
            updateDiffButtons(); notify(format(L["N_DIFF_SET"],"|cFF"..DIFFICULTIES[n].color..DIFFICULTIES[n].name.."|r"))
        else notify(L["N_DIFF_RANGE"]) end
    elseif msg=="help" or msg=="ayuda" then
        print("|cFFFFD700"..L["HELP_HEADER"].."|r")
        print(L["HELP_OPEN"]); print(L["HELP_ACCEPT"]); print(L["HELP_DECLINE"])
        print(L["HELP_RESIGN"]); print(L["HELP_RESTART"]); print(L["HELP_HISTORY"])
        print(L["HELP_DIFF"]); print(L["HELP_TAB"])
        print("|cFFFFD700"..L["HELP_FOOTER"].."|r")
    else
        notify(L["N_UNKNOWN_CMD"])
        if not (ChessFrame and ChessFrame:IsShown()) then API.ShowBoard() end
    end
end

SLASH_CHESS1="/chess"
SLASH_CHESS2="/ajedrez"
SlashCmdList["CHESS"]=slashCmd
