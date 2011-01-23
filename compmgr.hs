




-- open display
-- get screen
-- get root
-- query extensions?

import Data.Bits
import Data.Maybe
import Data.List ( delete )
import Control.Monad
import Foreign.C.Types( CInt )
import Foreign.Ptr
import Foreign.Marshal( alloca )
import Foreign.Storable( peek )
import System.IO

import Graphics.X11.Xdamage
import Graphics.X11.Types
import Graphics.X11.Xlib.Types
import Graphics.X11.Xlib.Display
import Graphics.X11.Xlib.Misc
import Graphics.X11.Xlib.Extras
import Graphics.X11.Xlib.Event

data Win = Win {  win_window :: Window
                , win_damage :: Maybe Damage
                , win_damaged :: Bool
               } deriving (Show, Eq)

-- Find a Win in winlist by its corresponding X window
findWin :: [Win] -> Window -> Maybe Win
findWin winlist win 
    | null matched = Nothing
    | otherwise = Just $ head matched -- there should never be more than one match
    where matched = filter (\x -> win_window x == win) winlist

-- Replace a Win in winlist with an updated version
updateWin :: [Win] -> Win -> [Win]
updateWin winlist win = [win] ++ (filter (\x -> x /= win) winlist)

-- Remove a Win from the winlist
delWin :: [Win] -> Win -> [Win]
delWin winlist win = delete win winlist


eventHandler :: Display -> [Win] -> CInt -> Event -> IO [Win]
eventHandler display winlist damage_ver ev
    | evtype == createNotify = addWin display winlist event_win
    | evtype == configureNotify = defaultHandler
    | evtype == destroyNotify && isJust maybewin = do
            when (isJust maybedamage) $ do
                xdamageDestroy display damage
            return $ delWin winlist win
    | evtype == mapNotify = defaultHandler
    | evtype == unmapNotify = defaultHandler
    | evtype == reparentNotify = defaultHandler
    | evtype == circulateNotify =  defaultHandler
    | evtype == expose = defaultHandler
    | evtype == propertyNotify = defaultHandler
    | evtype == (fromIntegral damage_ver) && isJust maybewin && isJust maybedamage = do
            xdamageSubtract display damage nullPtr nullPtr
            return $ updateWin winlist $ win { win_damaged=True }
    | otherwise = defaultHandler
    where
        defaultHandler = return winlist
        evtype = ev_event_type ev
        event_win = ev_window ev
        maybewin = findWin winlist event_win
        win = fromJust maybewin
        maybedamage = win_damage win
        damage = fromJust maybedamage



eventLoop :: Display -> [Win] -> CInt -> XEventPtr -> IO [Win]
eventLoop display winlist damage_ver e = do
    nextEvent display e
    ev <- getEvent e
    let evtype = ev_event_type ev
        event_win = ev_window ev
    when (((event_win /= 176) && (event_win /= 62914566)) || (evtype /= (fromIntegral damage_ver))) $
        print $ (evtypeToString evtype) ++ " event on window " ++ (show event_win) 
    eventHandler display winlist damage_ver ev
    where
        evtypeToString evtype
            | evtype == createNotify = "Create"
            | evtype == configureNotify = "Configure"
            | evtype == destroyNotify = "Destroy"
            | evtype == mapNotify = "Map"
            | evtype == unmapNotify = "Unmap"
            | evtype == reparentNotify = "Reparent"
            | evtype == circulateNotify = "Circulate"
            | evtype == expose = "Expose"
            | evtype == propertyNotify = "Property"
            | evtype == fromIntegral damage_ver = "Damage"
            | otherwise = "Unknown (" ++ (show evtype) ++ ")"


addWin :: Display -> [Win] -> Window -> IO [Win]
addWin display winlist win =
    if isJust $ findWin winlist win then return winlist
    else alloca $ \wa -> do
        status <- xGetWindowAttributes display win wa
        if status == 0 then return winlist
            else do
            attrs <- peek wa
            damage <- if wa_class attrs /= inputOutput then return Nothing
                      else do d <- xdamageCreate display win 3; return $ Just d
            name <- fetchName display win
            return $ winlist ++ [Win {win_window=win, win_damage=damage, win_damaged=False}]

main :: IO ()
main = do
    display <- openDisplay ""
    let screen = defaultScreen display
    rootwin <- rootWindow display screen
    damage <- xdamageQueryExtension display
    if isNothing damage then do
        print "XDamage extension not available, exiting."
        return ()
        else do
        let damage_ver = fst $ fromJust damage
            damage_err = snd $ fromJust damage

        print $ "DamageVer: " ++ (show damage_ver)

        selectInput display rootwin  $  substructureNotifyMask
                                    .|. exposureMask
                                    .|. structureNotifyMask 
                                    .|. propertyChangeMask

        sync display False
        xSetErrorHandler

        hSetBuffering stdout NoBuffering

        print $ "ROOT" ++ show rootwin

        grabServer display
        window_query <- queryTree display rootwin
        let children = (\(_,_,x) -> x) window_query
            winlist = [] :: [Win]
        winlist <- foldM (addWin display) winlist children
        winlist <- addWin display winlist rootwin
        ungrabServer display
        print $ "Winlist: " ++ (show winlist)


        allocaXEvent $ \e -> do
            let mainloop = \wlist evptr -> do
                    winlist <- eventLoop display wlist damage_ver evptr
                    mainloop winlist evptr
            mainloop winlist e
            


